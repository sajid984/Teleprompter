import Foundation
import Network
import Observation
import UIKit

/// A tiny HTTP server that lets a Mac, iPhone or another iPad on the same Wi-Fi control the prompter
/// from a web browser. It only accepts connections from private local-network addresses, never from
/// the internet, and every API call needs the 6-digit code shown on the iPad.
@MainActor
@Observable
final class RemoteServer {
    enum Status: Equatable {
        case off
        case starting
        case running(port: UInt16)
        case waiting(String)
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var code: String
    private(set) var addresses: [String] = []
    /// Devices that talked to the server in the last few seconds.
    private(set) var connectedDevices = 0

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// The address to open on the other device, with the code in the fragment so a QR scan pairs automatically.
    var pairingURL: String? {
        guard case .running(let port) = status, let ip = addresses.first else { return nil }
        return "http://\(ip):\(port)/#code=\(code)"
    }

    var displayURL: String? {
        guard case .running(let port) = status, let ip = addresses.first else { return nil }
        return "http://\(ip):\(port)"
    }

    @ObservationIgnored private let scripts: ScriptStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let session: PrompterSession
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var port: UInt16 = RemoteServer.preferredPort
    @ObservationIgnored private var portAttempts = 0
    @ObservationIgnored private var lastSeen: [String: Date] = [:]
    @ObservationIgnored private var failedAttempts: [String: Int] = [:]
    @ObservationIgnored private var blockedUntil: [String: Date] = [:]
    @ObservationIgnored private var housekeeping: Timer?

    private static let preferredPort: UInt16 = 8080
    private static let enabledKey = "remote.enabled"
    private static let codeKey = "remote.code"
    private static let maxRequestBytes = 2_000_000

    init(scripts: ScriptStore, settings: SettingsStore, session: PrompterSession) {
        self.scripts = scripts
        self.settings = settings
        self.session = session
        code = UserDefaults.standard.string(forKey: Self.codeKey) ?? Self.makeCode()
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        UserDefaults.standard.set(code, forKey: Self.codeKey)
        if isEnabled { start() }
    }

    // MARK: - Lifecycle

    func newCode() {
        code = Self.makeCode()
        UserDefaults.standard.set(code, forKey: Self.codeKey)
        lastSeen.removeAll()
        connectedDevices = 0
    }

    /// iOS suspends the app in the background, so the listener is closed there and reopened on return.
    func appBecameActive() {
        refreshAddresses()
        if isEnabled && listener == nil { start() }
    }

    func appEnteredBackground() {
        closeListener()
        if isEnabled { status = .off }
    }

    func refreshAddresses() {
        let found = Self.localIPv4Addresses()
        if found != addresses { addresses = found }
    }

    private func start() {
        guard listener == nil else { return }
        refreshAddresses()

        let parameters = NWParameters.tcp
        // Note: NWParameters.acceptLocalOnly rejects same-Wi-Fi connections too, so the
        // local-network check is done per connection in `privateRemoteAddress(of:)`.
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let newListener = try? NWListener(using: parameters, on: nwPort) else {
            status = .failed("Could not open port \(port).")
            return
        }
        newListener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener = newListener
        status = .starting
        newListener.start(queue: .main)

        housekeeping?.invalidate()
        housekeeping = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tidyUp() }
        }
    }

    private func stop() {
        closeListener()
        status = .off
        port = Self.preferredPort
        portAttempts = 0
        lastSeen.removeAll()
        connectedDevices = 0
    }

    private func closeListener() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        housekeeping?.invalidate()
        housekeeping = nil
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = .running(port: listener?.port?.rawValue ?? port)
            refreshAddresses()
        case .waiting(let error):
            status = .waiting("Waiting for Wi-Fi (\(error.localizedDescription))")
        case .failed(let error):
            closeListener()
            if case .posix(let posix) = error, posix == .EADDRINUSE, portAttempts < 10 {
                port += 1
                portAttempts += 1
                start()
            } else {
                status = .failed(error.localizedDescription)
            }
        default:
            break
        }
    }

    private func tidyUp() {
        refreshAddresses()
        let cutoff = Date().addingTimeInterval(-8)
        lastSeen = lastSeen.filter { $0.value > cutoff }
        if lastSeen.count != connectedDevices { connectedDevices = lastSeen.count }
        blockedUntil = blockedUntil.filter { $0.value > Date() }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard let ip = Self.privateRemoteAddress(of: connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        // Drop connections that never finish sending a request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { connection.cancel() }
        receive(on: connection, from: ip, buffer: Data())
    }

    private func receive(on connection: NWConnection, from ip: String, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }

                switch HTTPRequest.parse(buffer) {
                case .complete(let request):
                    self.respond(self.handle(request, from: ip), on: connection)
                case .invalid:
                    self.respond(.text("Bad request", status: 400), on: connection)
                case .incomplete:
                    if error != nil || isComplete || buffer.count > Self.maxRequestBytes {
                        connection.cancel()
                    } else {
                        self.receive(on: connection, from: ip, buffer: buffer)
                    }
                }
            }
        }
    }

    private func respond(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Routing

    private func handle(_ request: HTTPRequest, from ip: String) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return .html(RemotePage.html)
        default:
            break
        }
        guard request.path.hasPrefix("/api/") else { return .text("Not found", status: 404) }

        if let until = blockedUntil[ip], until > Date() {
            return .error("Too many wrong codes. Wait a few minutes and try again.", status: 429)
        }
        guard request.headers["x-remote-code"] == code else {
            let count = (failedAttempts[ip] ?? 0) + 1
            if count >= 10 {
                failedAttempts[ip] = nil
                blockedUntil[ip] = Date().addingTimeInterval(300)
            } else {
                failedAttempts[ip] = count
            }
            return .error("Wrong code", status: 401)
        }
        failedAttempts[ip] = nil
        if lastSeen[ip] == nil { connectedDevices = lastSeen.count + 1 }
        lastSeen[ip] = Date()

        switch (request.method, request.path) {
        case ("GET", "/api/state"):
            return .json(currentState())
        case ("POST", "/api/command"):
            guard let command = try? JSONDecoder().decode(RemoteCommand.self, from: request.body) else {
                return .error("Bad command", status: 400)
            }
            return perform(command)
        case ("GET", "/api/scripts"):
            return .json(scripts.scripts.map(ScriptSummary.init))
        case ("GET", "/api/preview"):
            guard let payload = previewPayload() else { return .error("No script is open", status: 409) }
            return .json(payload)
        case ("POST", "/api/scripts"):
            guard let new = try? JSONDecoder().decode(NewScript.self, from: request.body) else {
                return .error("Bad script", status: 400)
            }
            let body = new.clean ? TextCleanup.quickClean(new.body) : new.body
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("The script is empty", status: 400)
            }
            let script = scripts.create(title: new.title.trimmingCharacters(in: .whitespacesAndNewlines), body: body)
            if new.open { session.activeScript = script }
            return .json(ScriptSummary(script))
        case ("POST", "/api/start"):
            guard let start = try? JSONDecoder().decode(StartRequest.self, from: request.body),
                  let id = UUID(uuidString: start.id),
                  let script = scripts.script(with: id) else {
                return .error("Script not found", status: 404)
            }
            if session.activeScript?.id != script.id { session.activeScript = script }
            return .json(currentState())
        default:
            return .error("Not found", status: 404)
        }
    }

    private func perform(_ command: RemoteCommand) -> HTTPResponse {
        let engine = session.engine
        let needsPrompter: Set<String> = ["toggle", "play", "pause", "top", "back", "forward", "lineBack", "lineForward", "seek"]
        if needsPrompter.contains(command.action), engine == nil {
            return .error("Open a script on the iPad first", status: 409)
        }

        switch command.action {
        case "toggle": engine?.togglePlay()
        case "play": engine?.play()
        case "pause": engine?.pause()
        case "top": engine?.rewind()
        case "back": engine?.page(-1)
        case "forward": engine?.page(1)
        case "lineBack": engine?.nudge(lines: -1)
        case "lineForward": engine?.nudge(lines: 1)
        case "seek":
            guard let value = command.value else { return .error("Missing position", status: 400) }
            engine?.seek(toCharacter: Int(value), delta: command.delta ?? 0)
        case "speedUp": changeSpeed(by: 1)
        case "speedDown": changeSpeed(by: -1)
        case "setSpeed":
            guard let value = command.value else { return .error("Missing speed", status: 400) }
            changeSpeed(by: value.rounded() - settings.settings.speed)
        case "fontUp": changeFontSize(by: 4)
        case "fontDown": changeFontSize(by: -4)
        case "mirror":
            if let engine { engine.toggleMirror() } else { settings.settings.mirrorHorizontal.toggle() }
        case "close":
            session.activeScript = nil
        default:
            return .error("Unknown command", status: 400)
        }
        return .json(currentState())
    }

    /// Everything the web page needs to draw a scaled copy of the prompter text.
    private func previewPayload() -> PreviewPayload? {
        guard let script = session.activeScript else { return nil }
        let s = settings.settings
        let font = s.uiFont()
        let size = previewViewSize()
        return PreviewPayload(
            scriptId: script.id.uuidString,
            text: PrompterTextController.displayText(script.body, settings: s),
            font: s.fontFamily.cssFamily,
            weight: s.fontWeight.cssWeight,
            fontSize: s.fontSize,
            lineHeight: Double(font.lineHeight / font.pointSize) * s.lineSpacing,
            paragraphSpacing: 0.25,
            marginPercent: s.marginPercent,
            alignment: s.alignment == .center ? "center" : s.alignment == .trailing ? "right" : "left",
            textColor: s.textColor.css,
            backgroundColor: s.backgroundColor.css,
            markerColor: s.markerColor.css,
            markerPosition: s.markerPosition,
            viewWidth: Double(size.width),
            viewHeight: Double(size.height),
            revision: previewRevision()
        )
    }

    private func previewViewSize() -> CGSize {
        let size = session.engine?.viewSize ?? .zero
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 1180, height: 820)
    }

    /// Changes whenever the preview must be redrawn (another script, text style, rotation).
    private func previewRevision() -> Int {
        guard let script = session.activeScript else { return 0 }
        let s = settings.settings
        let size = previewViewSize()
        let key = "\(script.id)|\(script.body.count)|\(s.textStyle)|\(s.marginPercent)|\(s.markerPosition)|\(s.backgroundColor)|\(s.markerColor)|\(Int(size.width))x\(Int(size.height))"
        return key.hashValue & 0x7FFF_FFFF
    }

    private func changeSpeed(by delta: Double) {
        guard delta != 0 else { return }
        if let engine = session.engine {
            engine.adjustSpeed(by: delta)
        } else {
            let r = PrompterSettings.speedRange
            settings.settings.speed = min(max((settings.settings.speed + delta).rounded(), r.lowerBound), r.upperBound)
        }
    }

    private func changeFontSize(by delta: Double) {
        if let engine = session.engine {
            engine.adjustFontSize(by: delta)
        } else {
            let r = PrompterSettings.fontSizeRange
            settings.settings.fontSize = min(max(settings.settings.fontSize + delta, r.lowerBound), r.upperBound)
        }
    }

    private func currentState() -> RemoteState {
        let engine = session.engine
        let active = session.activeScript
        let s = settings.settings
        let anchor = engine?.anchor
        return RemoteState(
            prompterOpen: active != nil,
            scriptId: active?.id.uuidString,
            title: active?.displayTitle,
            playing: engine?.isPlaying ?? false,
            countdown: engine?.countdownValue,
            progress: engine?.progress ?? 0,
            elapsed: engine?.elapsedSeconds ?? 0,
            remaining: engine?.remainingSeconds ?? 0,
            reachedEnd: engine?.reachedEnd ?? false,
            speed: Int(s.speed),
            fontSize: Int(s.fontSize),
            mirror: s.mirrorHorizontal,
            anchor: anchor?.index,
            anchorDelta: anchor?.delta ?? 0,
            pointsPerSecond: Double(engine?.pointsPerSecond ?? 0),
            previewRevision: previewRevision(),
            scriptsRevision: scripts.scripts.map { $0.id.uuidString + $0.displayTitle + "\($0.body.count)" }
                .joined().hashValue & 0x7FFF_FFFF   // small enough for a JavaScript number
        )
    }

    // MARK: - Network helpers

    private static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// Returns the caller's address only when it is on a private / local network.
    private static func privateRemoteAddress(of endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let address):
            return isPrivate(address) ? "\(address)" : nil
        case .ipv6(let address):
            if let v4 = address.asIPv4 { return isPrivate(v4) ? "\(v4)" : nil }
            let bytes = [UInt8](address.rawValue)
            let isLinkLocal = bytes.count == 16 && bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
            let isUniqueLocal = bytes.count == 16 && (bytes[0] & 0xFE) == 0xFC
            return (address.isLoopback || isLinkLocal || isUniqueLocal) ? "\(address)" : nil
        default:
            return nil
        }
    }

    private static func isPrivate(_ address: IPv4Address) -> Bool {
        let b = [UInt8](address.rawValue)
        guard b.count == 4 else { return false }
        return b[0] == 10
            || (b[0] == 172 && (16...31).contains(b[1]))
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254)
            || b[0] == 127
    }

    /// Private IPv4 addresses of this device, Wi-Fi (en0) first.
    private static func localIPv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [(name: String, ip: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            if let v4 = IPv4Address(ip), isPrivate(v4) { found.append((name, ip)) }
        }
        let ordered = found.sorted { ($0.name == "en0" ? 0 : 1, $0.name) < ($1.name == "en0" ? 0 : 1, $1.name) }
        var seen = Set<String>()
        return ordered.map(\.ip).filter { seen.insert($0).inserted }
    }
}

// MARK: - API payloads

private struct RemoteCommand: Decodable {
    let action: String
    let value: Double?
    let delta: Double?
}

private struct PreviewPayload: Encodable {
    let scriptId: String
    let text: String
    let font: String
    let weight: Int
    let fontSize: Double
    let lineHeight: Double          // line pitch as a multiple of the font size
    let paragraphSpacing: Double    // em
    let marginPercent: Double
    let alignment: String
    let textColor: String
    let backgroundColor: String
    let markerColor: String
    let markerPosition: Double
    let viewWidth: Double
    let viewHeight: Double
    let revision: Int
}

private extension RGBAColor {
    var css: String { "rgb(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))" }
}

private extension FontFamily {
    var cssFamily: String {
        switch self {
        case .system: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
        case .rounded: "ui-rounded, -apple-system, system-ui, sans-serif"
        case .serif: "ui-serif, 'New York', Georgia, serif"
        case .mono: "ui-monospace, Menlo, monospace"
        case .helvetica: "'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .avenir: "'Avenir Next', Avenir, sans-serif"
        case .arial: "Arial, sans-serif"
        case .verdana: "Verdana, sans-serif"
        case .gillSans: "'Gill Sans', 'Gill Sans MT', sans-serif"
        case .futura: "Futura, sans-serif"
        case .georgia: "Georgia, serif"
        case .times: "'Times New Roman', Times, serif"
        case .baskerville: "Baskerville, serif"
        case .courier: "'Courier New', Courier, monospace"
        }
    }
}

private extension FontWeightOption {
    var cssWeight: Int {
        switch self {
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        }
    }
}

private struct NewScript: Decodable {
    let title: String
    let body: String
    let clean: Bool
    let open: Bool
}

private struct StartRequest: Decodable {
    let id: String
}

private struct ScriptSummary: Encodable {
    let id: String
    let title: String
    let words: Int

    init(_ script: Script) {
        id = script.id.uuidString
        title = script.displayTitle
        words = TextStats.wordCount(script.body)
    }
}

private struct RemoteState: Encodable {
    let prompterOpen: Bool
    let scriptId: String?
    let title: String?
    let playing: Bool
    let countdown: Int?
    let progress: Double
    let elapsed: Int
    let remaining: Int
    let reachedEnd: Bool
    let speed: Int
    let fontSize: Int
    let mirror: Bool
    let anchor: Int?
    let anchorDelta: Double
    let pointsPerSecond: Double
    let previewRevision: Int
    let scriptsRevision: Int
}

// MARK: - Minimal HTTP/1.1

private struct HTTPRequest {
    enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> ParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0 else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let body = data.subdata(in: bodyStart..<data.index(bodyStart, offsetBy: length))

        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path, headers: headers, body: body))
    }
}

private struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data

    static func html(_ html: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    static func text(_ text: String, status: Int) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }

    var serialized: Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 429: reason = "Too Many Requests"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Referrer-Policy: no-referrer\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
