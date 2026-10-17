import SwiftUI
import UniformTypeIdentifiers

/// Script list on the left, editor on the right.
struct LibraryView: View {
    @Environment(ScriptStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PrompterSession.self) private var session
    @Environment(RemoteServer.self) private var remoteServer

    @State private var selection: Script.ID?
    @State private var showSettings = false
    @State private var showRemote = false
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        @Bindable var session = session
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.scripts) { script in
                    ScriptRow(script: script, wordsPerMinute: settingsStore.settings.wordsPerMinute)
                        .tag(script.id)
                        .contextMenu {
                            Button("Start Prompter", systemImage: "play.fill") { session.activeScript = script }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                if let copy = store.duplicate(script.id) { selection = copy.id }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete([script.id]) }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete([script.id]) }
                        }
                }
            }
            .navigationTitle("Scripts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Label("Display Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showRemote = true } label: {
                        Label("Remote Control", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tint(remoteServer.isRunning ? .green : nil)
                    // Tap: new script. Long-press: also offers importing a text file.
                    Menu {
                        Button("New Script", systemImage: "square.and.pencil") { selection = store.create().id }
                        Button("Import Text File…", systemImage: "square.and.arrow.down") { showImporter = true }
                    } label: {
                        Label("New Script", systemImage: "square.and.pencil")
                    } primaryAction: {
                        selection = store.create().id
                    }
                }
            }
            .overlay {
                if store.scripts.isEmpty {
                    ContentUnavailableView {
                        Label("No Scripts", systemImage: "text.alignleft")
                    } description: {
                        Text("Tap the new script button to add one.")
                    }
                }
            }
        } detail: {
            if let id = selection, let script = store.script(with: id) {
                EditorView(script: script) { session.activeScript = $0 }
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Script Selected", systemImage: "text.alignleft")
                } description: {
                    Text("Pick a script from the list, or create a new one and paste your text.")
                } actions: {
                    Button("New Script") { selection = store.create().id }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = store.scripts.first?.id }
        }
        .fullScreenCover(item: $session.activeScript) { script in
            PrompterView(script: script, settingsStore: settingsStore)
                .environment(settingsStore)
                .environment(session)
        }
        .sheet(isPresented: $showRemote) {
            RemoteControlView()
                .environment(remoteServer)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsForm()
                    .navigationTitle("Display Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            .environment(settingsStore)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.plainText, .rtf],
                      allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Could not import", isPresented: Binding(get: { importError != nil },
                                                         set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func delete(_ ids: Set<Script.ID>) {
        let wasSelected = selection.map(ids.contains) ?? false
        store.delete(ids)
        if wasSelected { selection = store.scripts.first?.id }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failed: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let text = Self.readText(url) else {
                    failed.append(url.lastPathComponent)
                    continue
                }
                let body = settingsStore.settings.autoCleanOnPaste ? TextCleanup.quickClean(text) : text
                selection = store.create(title: url.deletingPathExtension().lastPathComponent, body: body).id
            }
            if !failed.isEmpty {
                importError = "These files could not be read as text: " + failed.joined(separator: ", ")
            }
        }
    }

    private static func readText(_ url: URL) -> String? {
        if url.pathExtension.lowercased() == "rtf" {
            return try? NSAttributedString(url: url,
                                           options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil).string
        }
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let text = try? String(contentsOf: url, encoding: encoding) { return text }
        }
        return nil
    }
}

private struct ScriptRow: View {
    let script: Script
    let wordsPerMinute: Int

    var body: some View {
        let words = TextStats.wordCount(script.body)
        VStack(alignment: .leading, spacing: 4) {
            Text(script.displayTitle)
                .font(.headline)
                .lineLimit(1)
            if !script.preview.isEmpty {
                Text(script.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(words) words · about \(TextStats.clock(words * 60 / max(wordsPerMinute, 1)))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
