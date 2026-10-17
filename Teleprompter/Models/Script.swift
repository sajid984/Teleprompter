import Foundation
import Observation

struct Script: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String = ""
    var body: String = ""
    var updatedAt = Date()

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return firstLine.isEmpty ? "Untitled Script" : String(firstLine.prefix(48))
    }

    var preview: String {
        String(body.prefix(240))
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static let welcome = Script(
        title: "Welcome to Teleprompter",
        body: """
        Welcome! This is a sample script.

        Tap Start to run it full screen. Tap anywhere on the text to pause or play, and drag the text to move back or forward.

        Use the bar at the bottom to change the scrolling speed and the text size, mirror the text for teleprompter glass, or open the display settings for fonts, colours, margins and the reading guide.

        To add your own script, tap the new script button and paste your text. The Clean Up menu removes extra blank lines, punctuation, and notes in brackets.

        With a keyboard or a Bluetooth remote: Space plays and pauses, the left and right arrows change the speed, and the up and down arrows nudge the text.

        Happy recording!
        """
    )
}

/// Saves scripts as JSON in Application Support. Writes are debounced while typing.
@MainActor
@Observable
final class ScriptStore {
    private(set) var scripts: [Script] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("scripts.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
        } else {
            scripts = [.welcome]
            saveNow()
        }
    }

    func script(with id: Script.ID) -> Script? {
        scripts.first { $0.id == id }
    }

    @discardableResult
    func create(title: String = "", body: String = "") -> Script {
        let script = Script(title: title, body: body)
        scripts.insert(script, at: 0)
        scheduleSave()
        return script
    }

    func update(_ script: Script) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        guard scripts[index].title != script.title || scripts[index].body != script.body else { return }
        var updated = script
        updated.updatedAt = Date()
        scripts[index] = updated
        scheduleSave()
    }

    @discardableResult
    func duplicate(_ id: Script.ID) -> Script? {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return nil }
        let original = scripts[index]
        let copy = Script(title: original.displayTitle + " copy", body: original.body)
        scripts.insert(copy, at: index + 1)
        scheduleSave()
        return copy
    }

    func delete(_ ids: Set<Script.ID>) {
        scripts.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let data = try JSONEncoder().encode(scripts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Teleprompter: could not save scripts: \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
