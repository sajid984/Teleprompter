import SwiftUI

/// The full-screen prompter: scrolling text, countdown, transient HUD, and a control bar that hides while playing.
struct PrompterView: View {
    let script: Script

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PrompterSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var engine: PrompterEngine
    @State private var controlsVisible = true
    @State private var showSettings = false
    @State private var hideTask: Task<Void, Never>?

    init(script: Script, settingsStore: SettingsStore) {
        self.script = script
        _engine = State(initialValue: PrompterEngine(settingsStore: settingsStore))
    }

    private var settings: PrompterSettings { settingsStore.settings }

    var body: some View {
        ZStack {
            settings.backgroundColor.color.ignoresSafeArea()

            PrompterSurface(text: script.body,
                            settings: settings,
                            engine: engine,
                            keyFocusEnabled: !showSettings,
                            onTap: handleTap)
                .ignoresSafeArea()

            CountdownOverlay(engine: engine, settings: settings)
            HUDOverlay(engine: engine)

            PrompterControls(script: script,
                             engine: engine,
                             showSettings: $showSettings,
                             onClose: close,
                             onInteraction: revealControls)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            engine.onExitRequest = { dismiss() }
            session.engine = engine
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            engine.stop()
            if session.engine === engine { session.engine = nil }
        }
        .onChange(of: engine.isPlaying) { _, playing in
            if playing {
                scheduleAutoHide()
            } else {
                hideTask?.cancel()
                controlsVisible = true
            }
        }
        .onChange(of: settings.speed) { _, _ in engine.refreshMetrics() }
        .onChange(of: showSettings) { _, open in
            if open { hideTask?.cancel() } else { scheduleAutoHide() }
        }
    }

    private func handleTap() {
        if settings.tapToPause {
            engine.togglePlay()
            revealControls()
        } else if controlsVisible && engine.isPlaying {
            hideTask?.cancel()
            controlsVisible = false
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        controlsVisible = true
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard settings.autoHideControls else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, engine.isPlaying || engine.countdownValue != nil, !showSettings else { return }
            controlsVisible = false
        }
    }

    private func close() {
        engine.stop()
        dismiss()
    }
}

// MARK: - Control bar

private struct PrompterControls: View {
    let script: Script
    let engine: PrompterEngine
    @Binding var showSettings: Bool
    let onClose: () -> Void
    let onInteraction: () -> Void

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel("Close prompter")

            Text(script.displayTitle)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Label(TextStats.clock(engine.elapsedSeconds), systemImage: "clock")
                Text("−" + TextStats.clock(engine.remainingSeconds))
                    .foregroundStyle(.secondary)
                ProgressView(value: engine.progress)
                    .frame(width: 110)
                    .tint(.accentColor)
            }
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(showSlider: true)
            barContent(showSlider: false)
            ScrollView(.horizontal, showsIndicators: false) { barContent(showSlider: false) }
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            NavigationStack {
                SettingsForm(showsEditorSections: false)
                    .navigationTitle("Display")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            .frame(minWidth: 400, idealWidth: 440, minHeight: 520, idealHeight: 700)
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
            .environment(settingsStore)
        }
    }

    private func barContent(showSlider: Bool) -> some View {
        let settings = settingsStore.settings
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                barButton("backward.end.fill", "Back to top") { engine.rewind() }
                barButton("gobackward.5", "Scroll back") { engine.page(-1) }
                Button { act { engine.togglePlay() } } label: {
                    Image(systemName: engine.isPlaying || engine.countdownValue != nil ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor, in: Circle())
                }
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                barButton("goforward.5", "Scroll forward") { engine.page(1) }
            }

            divider

            HStack(spacing: 4) {
                Image(systemName: "speedometer").foregroundStyle(.secondary)
                barButton("minus", "Slower") { engine.adjustSpeed(by: -1) }
                Text("\(Int(settings.speed))")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 40)
                barButton("plus", "Faster") { engine.adjustSpeed(by: 1) }
                if showSlider {
                    Slider(value: speedBinding, in: PrompterSettings.speedRange, step: 1) { editing in
                        if !editing { onInteraction() }
                    }
                    .frame(width: 170)
                }
            }

            divider

            HStack(spacing: 4) {
                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                barButton("textformat.size.smaller", "Smaller text") { engine.adjustFontSize(by: -4) }
                Text("\(Int(settings.fontSize))")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 44)
                barButton("textformat.size.larger", "Bigger text") { engine.adjustFontSize(by: 4) }
            }

            divider

            HStack(spacing: 6) {
                Button { act { engine.toggleMirror() } } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(settings.mirrorHorizontal ? Color.accentColor : Color.clear, in: Circle())
                }
                .accessibilityLabel("Mirror text")
                barButton("slider.horizontal.3", "Display settings") { showSettings = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 36)
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { settingsStore.settings.speed },
                set: { settingsStore.settings.speed = $0 })
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { act(action) } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func act(_ action: () -> Void) {
        action()
        onInteraction()
    }
}

// MARK: - Overlays

private struct CountdownOverlay: View {
    let engine: PrompterEngine
    let settings: PrompterSettings

    var body: some View {
        if let n = engine.countdownValue {
            Text("\(n)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .foregroundStyle(settings.textColor.color)
                .contentTransition(.numericText(countsDown: true))
                .frame(width: 300, height: 300)
                .background(settings.backgroundColor.color.opacity(0.6), in: Circle())
                .overlay(Circle().stroke(settings.textColor.color.opacity(0.3), lineWidth: 4))
                .scaleEffect(x: settings.mirrorHorizontal ? -1 : 1, y: settings.mirrorVertical ? -1 : 1)
                .animation(.snappy, value: n)
                .allowsHitTesting(false)
        }
    }
}

private struct HUDOverlay: View {
    let engine: PrompterEngine

    var body: some View {
        VStack {
            if let hud = engine.hud {
                Text(hud.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .padding(.top, 90)
                    .transition(.opacity)
                    .id(hud.id)
            }
            Spacer()
        }
        .animation(.easeOut(duration: 0.2), value: engine.hud)
        .allowsHitTesting(false)
    }
}
