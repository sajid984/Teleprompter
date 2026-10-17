import SwiftUI

/// All prompter options. Used as a sheet from the library and as a popover inside the prompter (live preview behind it).
struct SettingsForm: View {
    var showsEditorSections = true

    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                SettingsPreview(settings: store.settings)
                    .listRowInsets(EdgeInsets())
            }

            Section("Scrolling") {
                SettingSlider(title: "Speed", value: $store.settings.speed,
                              range: PrompterSettings.speedRange, step: 1) { "\(Int($0))" }
                Picker("Countdown before start", selection: $store.settings.countdown) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                Toggle("Tap the text to pause and play", isOn: $store.settings.tapToPause)
                Toggle("Hide controls while playing", isOn: $store.settings.autoHideControls)
            }

            Section("Text") {
                Picker("Font", selection: $store.settings.fontFamily) {
                    ForEach(FontFamily.allCases) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                Picker("Weight", selection: $store.settings.fontWeight) {
                    ForEach(FontWeightOption.allCases) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }
                SettingSlider(title: "Text size", value: $store.settings.fontSize,
                              range: PrompterSettings.fontSizeRange, step: 2) { "\(Int($0)) pt" }
                SettingSlider(title: "Line spacing", value: $store.settings.lineSpacing,
                              range: 0.9...2.5, step: 0.05) { String(format: "%.2f×", $0) }
                SettingSlider(title: "Side margins", value: $store.settings.marginPercent,
                              range: 0...0.3, step: 0.01) { "\(Int(($0 * 100).rounded()))%" }
                Picker("Alignment", selection: $store.settings.alignment) {
                    ForEach(TextAlignmentOption.allCases) { option in
                        Image(systemName: option.symbol)
                            .accessibilityLabel(option.displayName)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("ALL CAPS", isOn: $store.settings.uppercase)
            }

            Section("Colours") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ColorTheme.presets) { theme in
                            ThemeSwatch(theme: theme,
                                        selected: store.settings.textColor == theme.text
                                            && store.settings.backgroundColor == theme.background) {
                                store.settings.textColor = theme.text
                                store.settings.backgroundColor = theme.background
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                ColorPicker("Text colour", selection: colorBinding(\.textColor), supportsOpacity: false)
                ColorPicker("Background colour", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                ColorPicker("Guide arrow colour", selection: colorBinding(\.markerColor), supportsOpacity: false)
            }

            Section {
                Toggle("Mirror text (flip left–right)", isOn: $store.settings.mirrorHorizontal)
                Toggle("Flip upside down", isOn: $store.settings.mirrorVertical)
            } header: {
                Text("Mirror")
            } footer: {
                Text("Turn on Mirror when the iPad sits under teleprompter glass, so the reflection reads the right way round.")
            }

            Section("Reading guide") {
                Picker("Style", selection: $store.settings.markerStyle) {
                    ForEach(MarkerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                SettingSlider(title: "Position from top", value: $store.settings.markerPosition,
                              range: 0.1...0.8, step: 0.01) { "\(Int(($0 * 100).rounded()))%" }
                Toggle("Fade text at the top and bottom", isOn: $store.settings.fadeEdges)
            }

            if showsEditorSections {
                Section("Script editor") {
                    Toggle("Clean up pasted text automatically", isOn: $store.settings.autoCleanOnPaste)
                    Stepper(value: $store.settings.wordsPerMinute, in: 80...260, step: 10) {
                        LabeledContent("Reading pace for time estimates", value: "\(store.settings.wordsPerMinute) wpm")
                    }
                }

                Section {
                    ShortcutRow(keys: "Space / Return", action: "Play / pause")
                    ShortcutRow(keys: "← / →", action: "Slower / faster")
                    ShortcutRow(keys: "↑ / ↓", action: "Scroll back / forward a line")
                    ShortcutRow(keys: "Page Up / Page Down", action: "Jump back / forward")
                    ShortcutRow(keys: "Home", action: "Back to the top")
                    ShortcutRow(keys: "− / =", action: "Smaller / bigger text")
                    ShortcutRow(keys: "M", action: "Mirror on / off")
                    ShortcutRow(keys: "Esc", action: "Close the prompter")
                } header: {
                    Text("Keyboard & Bluetooth remote")
                } footer: {
                    Text("Most Bluetooth page-turner remotes send arrow or Page Up / Page Down keys and work with these shortcuts.")
                }
            }

            Section {
                Button("Reset all display settings", role: .destructive) {
                    store.reset()
                }
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<PrompterSettings, RGBAColor>) -> Binding<Color> {
        Binding(get: { store.settings[keyPath: keyPath].color },
                set: { store.settings[keyPath: keyPath] = RGBAColor($0) })
    }
}

struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}

/// A small live sample of the prompter look.
struct SettingsPreview: View {
    let settings: PrompterSettings

    var body: some View {
        GeometryReader { geo in
            let scale = 0.42
            let font = settings.uiFont(size: CGFloat(min(settings.fontSize * scale, 46)))
            ZStack(alignment: .topLeading) {
                settings.backgroundColor.color
                Text(settings.uppercase ? Self.sample.uppercased() : Self.sample)
                    .font(Font(font))
                    .foregroundStyle(settings.textColor.color)
                    .multilineTextAlignment(settings.alignment.swiftUI)
                    .lineSpacing(max(0, (settings.lineSpacing - 1) * font.lineHeight))
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .padding(.horizontal, geo.size.width * settings.marginPercent)
                    .padding(.top, geo.size.height * settings.markerPosition - font.lineHeight / 2)
                if settings.markerStyle != .none {
                    Rectangle()
                        .fill(settings.markerStyle == .arrows ? Color.clear : settings.textColor.color.opacity(0.3))
                        .frame(height: 2)
                        .offset(y: geo.size.height * settings.markerPosition - 1)
                }
            }
            .scaleEffect(x: settings.mirrorHorizontal ? -1 : 1, y: settings.mirrorVertical ? -1 : 1)
        }
        .frame(height: 170)
        .clipped()
        .accessibilityHidden(true)
    }

    private var frameAlignment: Alignment {
        switch settings.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static let sample = "Good morning everyone, and welcome. Today I want to share three simple ideas with you."
}

private struct ThemeSwatch: View {
    let theme: ColorTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Aa")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.text.color)
                .frame(width: 64, height: 48)
                .background(theme.background.color, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selected ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        LabeledContent(action) {
            Text(keys)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
