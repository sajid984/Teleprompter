import UIKit
import Observation

struct HUDMessage: Equatable {
    let id = UUID()
    let text: String
}

/// Drives the auto-scroll. Owns the display link and the scroll position; the text view only renders.
@MainActor
@Observable
final class PrompterEngine {
    private(set) var isPlaying = false
    private(set) var countdownValue: Int?
    private(set) var progress: Double = 0
    private(set) var elapsedSeconds = 0
    private(set) var remainingSeconds = 0
    private(set) var reachedEnd = false
    private(set) var hud: HUDMessage?

    @ObservationIgnored let settingsStore: SettingsStore
    @ObservationIgnored weak var scrollView: UIScrollView?
    /// Height of one line of text, set by the text view controller. Used for arrow-key nudges.
    @ObservationIgnored var linePitch: CGFloat = 80
    @ObservationIgnored var onExitRequest: (() -> Void)?
    /// Size of the prompter text area, set by the text view controller (used by the web remote's preview).
    @ObservationIgnored var viewSize: CGSize = .zero
    /// Character at the reading guide, plus how far (in lines) the guide is past that line's centre.
    @ObservationIgnored var anchorProvider: (() -> (index: Int, delta: Double)?)?
    /// Scroll offset that puts a character's line (plus `delta` lines) on the reading guide.
    @ObservationIgnored var offsetForAnchor: ((Int, Double) -> CGFloat?)?

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    /// Exact scroll position. Kept separately so sub-point steps at slow speeds are never lost to rounding.
    @ObservationIgnored private var position: CGFloat = 0
    @ObservationIgnored private var elapsed: TimeInterval = 0
    @ObservationIgnored private var isUserScrolling = false
    /// While the web remote is dragging the text, auto-scroll holds still until this time.
    @ObservationIgnored private var remoteHoldUntil: CFTimeInterval = 0
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Speed 1...100 scales with the font size, so a given speed moves the same number of lines per second at any size.
    var pointsPerSecond: CGFloat {
        let s = settingsStore.settings
        return CGFloat(s.speed * s.fontSize / 32)
    }

    // MARK: - Transport

    func togglePlay() {
        if isPlaying || countdownValue != nil { pause() } else { play() }
    }

    func play() {
        guard !isPlaying, countdownValue == nil, let sv = scrollView else { return }
        let range = offsetRange(sv)
        if reachedEnd || position >= range.upperBound - 0.5 {
            position = range.lowerBound
            elapsed = 0
            apply(sv, animated: false)
            publish(range)
        }
        reachedEnd = false

        let countdown = settingsStore.settings.countdown
        guard countdown > 0, position <= range.lowerBound + 0.5 else {
            startScrolling()
            return
        }
        countdownTask = Task { [weak self] in
            for n in stride(from: countdown, through: 1, by: -1) {
                self?.countdownValue = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.countdownValue = nil
            self?.startScrolling()
        }
    }

    func pause() {
        countdownTask?.cancel()
        countdownTask = nil
        if countdownValue != nil { countdownValue = nil }
        if isPlaying { isPlaying = false }
        displayLink?.invalidate()
        displayLink = nil
    }

    func stop() {
        pause()
        hudTask?.cancel()
    }

    func rewind() {
        guard let sv = scrollView else { return }
        let range = offsetRange(sv)
        position = range.lowerBound
        elapsed = 0
        reachedEnd = false
        apply(sv, animated: !isPlaying)
        publish(range)
    }

    var anchor: (index: Int, delta: Double)? {
        anchorProvider?()
    }

    /// Jumps so the given character sits on the reading guide (web remote live scrolling).
    func seek(toCharacter index: Int, delta: Double) {
        guard let sv = scrollView, let y = offsetForAnchor?(index, delta) else { return }
        let range = offsetRange(sv)
        position = min(max(y, range.lowerBound), range.upperBound)
        if position < range.upperBound - 1 { reachedEnd = false }
        remoteHoldUntil = CACurrentMediaTime() + 0.6
        apply(sv, animated: false)
        publish(range)
    }

    func nudge(lines: CGFloat) {
        move(by: lines * linePitch)
    }

    func page(_ direction: CGFloat) {
        guard let sv = scrollView else { return }
        move(by: direction * sv.bounds.height * 0.5)
    }

    // MARK: - Live adjustments

    func adjustSpeed(by delta: Double) {
        let r = PrompterSettings.speedRange
        let speed = min(max((settingsStore.settings.speed + delta).rounded(), r.lowerBound), r.upperBound)
        settingsStore.settings.speed = speed
        showHUD("Speed \(Int(speed))")
        refreshMetrics()
    }

    func adjustFontSize(by delta: Double) {
        let r = PrompterSettings.fontSizeRange
        let size = min(max(settingsStore.settings.fontSize + delta, r.lowerBound), r.upperBound)
        settingsStore.settings.fontSize = size
        showHUD("Text size \(Int(size))")
    }

    func toggleMirror() {
        settingsStore.settings.mirrorHorizontal.toggle()
        showHUD(settingsStore.settings.mirrorHorizontal ? "Mirror on" : "Mirror off")
    }

    func requestExit() {
        stop()
        onExitRequest?()
    }

    func showHUD(_ text: String) {
        let message = HUDMessage(text: text)
        hud = message
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, self?.hud?.id == message.id else { return }
            self?.hud = nil
        }
    }

    func refreshMetrics() {
        guard let sv = scrollView else { return }
        publish(offsetRange(sv))
    }

    // MARK: - Layout and manual scrolling (called by the text view controller)

    /// Runs a change that alters the text layout (font, margins, rotation) and keeps the reader at the same place.
    func preservingProgress(_ change: () -> Void) {
        guard let sv = scrollView else { change(); return }
        let old = offsetRange(sv)
        let span = old.upperBound - old.lowerBound
        let fraction = span > 0 ? min(max((position - old.lowerBound) / span, 0), 1) : 0
        change()
        let new = offsetRange(sv)
        position = new.lowerBound + fraction * (new.upperBound - new.lowerBound)
        apply(sv, animated: false)
        publish(new)
    }

    func userScrollBegan() {
        isUserScrolling = true
    }

    func userScrolled(to y: CGFloat) {
        guard let sv = scrollView else { return }
        let range = offsetRange(sv)
        position = min(max(y, range.lowerBound), range.upperBound)
        if reachedEnd, position < range.upperBound - 1 { reachedEnd = false }
        publish(range)
    }

    func userScrollEnded() {
        isUserScrolling = false
    }

    // MARK: - Private

    private func startScrolling() {
        isPlaying = true
        lastTimestamp = nil
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard let last = lastTimestamp, isPlaying, !isUserScrolling, now >= remoteHoldUntil,
              let sv = scrollView else { return }

        let dt = min(now - last, 1.0 / 20)
        elapsed += dt
        position += pointsPerSecond * CGFloat(dt)

        let range = offsetRange(sv)
        if position >= range.upperBound {
            position = range.upperBound
            apply(sv, animated: false)
            publish(range)
            pause()
            reachedEnd = true
            showHUD("End of script")
            return
        }
        apply(sv, animated: false)
        publish(range)
    }

    private func move(by delta: CGFloat) {
        guard let sv = scrollView else { return }
        let range = offsetRange(sv)
        position = min(max(position + delta, range.lowerBound), range.upperBound)
        if position < range.upperBound - 1 { reachedEnd = false }
        apply(sv, animated: !isPlaying)
        publish(range)
    }

    private func offsetRange(_ sv: UIScrollView) -> ClosedRange<CGFloat> {
        let lower = -sv.contentInset.top
        let upper = max(lower, sv.contentSize.height + sv.contentInset.bottom - sv.bounds.height)
        return lower...upper
    }

    private func apply(_ sv: UIScrollView, animated: Bool) {
        let target = CGPoint(x: -sv.contentInset.left, y: position)
        if animated {
            sv.setContentOffset(target, animated: true)
        } else {
            sv.contentOffset = target
        }
    }

    /// Publishes progress and times, only when they visibly change, so SwiftUI is not invalidated every frame.
    private func publish(_ range: ClosedRange<CGFloat>) {
        let span = range.upperBound - range.lowerBound
        let p = span > 0 ? Double(min(max((position - range.lowerBound) / span, 0), 1)) : 0
        if abs(p - progress) > 0.0005 || (p != progress && (p == 0 || p == 1)) { progress = p }

        let e = Int(elapsed)
        if e != elapsedSeconds { elapsedSeconds = e }

        let pps = pointsPerSecond
        let r = pps > 0 ? Int(((range.upperBound - position) / pps).rounded(.up)) : 0
        if r != remainingSeconds { remainingSeconds = r }
    }
}

/// CADisplayLink retains its target; this proxy keeps the engine free of that cycle.
@MainActor
private final class DisplayLinkProxy: NSObject {
    private let handler: (CADisplayLink) -> Void

    init(_ handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func step(_ link: CADisplayLink) {
        handler(link)
    }
}
