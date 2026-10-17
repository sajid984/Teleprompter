import SwiftUI

/// Edits one script: title, text, paste, clean-up tools with undo, and the Start button.
struct EditorView: View {
    let onStart: (Script) -> Void

    @Environment(ScriptStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @State private var draft: Script
    @State private var undoStack: [String] = []
    @State private var pendingPaste: String?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    init(script: Script, onStart: @escaping (Script) -> Void) {
        _draft = State(initialValue: script)
        self.onStart = onStart
    }

    private var isEmpty: Bool {
        draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Script title", text: $draft.title)
                .font(.title.bold())
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            actionBar
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Divider()

            TextEditor(text: $draft.body)
                .font(.system(size: 20))
                .lineSpacing(4)
                .focused($editorFocused)
                .padding(.horizontal, 15)
                .overlay {
                    if draft.body.isEmpty { emptyState }
                }

            Divider()
            statsBar
        }
        .navigationTitle(draft.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 56)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .onChange(of: draft) { _, newValue in store.update(newValue) }
        .onDisappear { store.update(draft) }
        .confirmationDialog("Paste script", isPresented: Binding(get: { pendingPaste != nil },
                                                                 set: { if !$0 { pendingPaste = nil } })) {
            Button("Replace the current text") { finishPaste(replace: true) }
            Button("Add to the end") { finishPaste(replace: false) }
            Button("Cancel", role: .cancel) { pendingPaste = nil }
        } message: {
            Text("This script already has text.")
        }
    }

    // MARK: - Pieces

    /// Full labels when there is room; icon-only Paste / Clean Up / Undo on narrow widths (portrait, Split View).
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            actionBarContent(compact: false)
            actionBarContent(compact: true)
        }
    }

    private func actionBarContent(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if compact {
                    pasteButton.labelStyle(.iconOnly)
                } else {
                    pasteButton.labelStyle(.titleAndIcon)
                }
            }
            .buttonBorderShape(.capsule)

            Menu {
                Section("Lines") {
                    cleanupButton("Remove Extra Blank Lines", "line.3.horizontal.decrease", TextCleanup.removeExtraBlankLines)
                    cleanupButton("Remove All Blank Lines", "rectangle.compress.vertical", TextCleanup.removeAllBlankLines)
                    cleanupButton("Join Broken Lines into Paragraphs", "text.alignleft", TextCleanup.joinBrokenLines)
                    cleanupButton("Blank Line Between Paragraphs", "paragraphsign", TextCleanup.blankLineBetweenParagraphs)
                }
                Section("Text") {
                    cleanupButton("Remove Punctuation", "textformat.abc", TextCleanup.removePunctuation)
                    cleanupButton("Remove [Notes] and (Directions)", "eraser", TextCleanup.removeBracketedNotes)
                    cleanupButton("Trim Extra Spaces", "scissors", TextCleanup.trimSpaces)
                    cleanupButton("Make UPPERCASE", "textformat", TextCleanup.uppercase)
                }
                Section {
                    cleanupButton("Quick Clean (spaces + extra lines)", "wand.and.stars", TextCleanup.quickClean)
                }
            } label: {
                barLabel("Clean Up", "wand.and.stars", compact: compact)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(isEmpty)

            Button {
                undo()
            } label: {
                barLabel("Undo", "arrow.uturn.backward", compact: compact)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(undoStack.isEmpty)

            Spacer(minLength: 8)

            Button {
                start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isEmpty)
        }
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            let text = strings.joined(separator: "\n")
            DispatchQueue.main.async { receivePaste(text) }
        }
    }

    private func barLabel(_ title: String, _ symbol: String, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            if !compact { Text(title).lineLimit(1) }
        }
        .fixedSize()
        .accessibilityLabel(title)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
            Text("Type your script here, or paste it")
                .font(.title3)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            pasteButton
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }

    private var statsBar: some View {
        let words = TextStats.wordCount(draft.body)
        let wpm = max(settingsStore.settings.wordsPerMinute, 1)
        let lines = draft.body.isEmpty ? 0 : draft.body.components(separatedBy: "\n").count
        return HStack(spacing: 18) {
            Label("\(words) words", systemImage: "text.word.spacing")
            Label("\(lines) lines", systemImage: "list.bullet")
            Label("about \(TextStats.clock(words * 60 / wpm)) at \(wpm) wpm", systemImage: "clock")
            Spacer()
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func cleanupButton(_ title: String, _ symbol: String, _ transform: @escaping (String) -> String) -> some View {
        Button(title, systemImage: symbol) { applyCleanup(title, transform) }
    }

    // MARK: - Actions

    private func receivePaste(_ text: String) {
        let incoming = settingsStore.settings.autoCleanOnPaste ? TextCleanup.quickClean(text) : text
        guard !incoming.isEmpty else { showToast("The clipboard has no text"); return }
        if isEmpty {
            pushUndo()
            draft.body = incoming
            showToast("Pasted")
        } else {
            pendingPaste = incoming
        }
    }

    private func finishPaste(replace: Bool) {
        guard let incoming = pendingPaste else { return }
        pendingPaste = nil
        pushUndo()
        if replace {
            draft.body = incoming
        } else {
            let separator = draft.body.hasSuffix("\n") ? "\n" : "\n\n"
            draft.body += separator + incoming
        }
        showToast(replace ? "Text replaced" : "Text added")
    }

    private func applyCleanup(_ title: String, _ transform: (String) -> String) {
        let cleaned = transform(draft.body)
        guard cleaned != draft.body else {
            showToast("Nothing to change")
            return
        }
        pushUndo()
        draft.body = cleaned
        showToast("Done: \(title)")
    }

    private func pushUndo() {
        undoStack.append(draft.body)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        draft.body = previous
        showToast("Undone")
    }

    private func start() {
        editorFocused = false
        store.update(draft)
        onStart(draft)
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}
