import SwiftUI
import UIKit
import Observation

struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
        self.init(clamp(r), clamp(g), clamp(b), clamp(a))
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    static let white = RGBAColor(1, 1, 1)
    static let black = RGBAColor(0, 0, 0)
}

enum FontFamily: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    case helvetica, avenir, arial, verdana, gillSans, futura
    case georgia, times, baskerville, courier

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System (SF Pro)"
        case .rounded: "Rounded"
        case .serif: "Serif (New York)"
        case .mono: "Monospaced"
        case .helvetica: "Helvetica Neue"
        case .avenir: "Avenir Next"
        case .arial: "Arial"
        case .verdana: "Verdana"
        case .gillSans: "Gill Sans"
        case .futura: "Futura"
        case .georgia: "Georgia"
        case .times: "Times New Roman"
        case .baskerville: "Baskerville"
        case .courier: "Courier New"
        }
    }

    /// Face names for regular, medium, semibold, bold, heavy.
    private var faces: [String]? {
        switch self {
        case .system, .rounded, .serif, .mono: nil
        case .helvetica: ["HelveticaNeue", "HelveticaNeue-Medium", "HelveticaNeue-Medium", "HelveticaNeue-Bold", "HelveticaNeue-Bold"]
        case .avenir: ["AvenirNext-Regular", "AvenirNext-Medium", "AvenirNext-DemiBold", "AvenirNext-Bold", "AvenirNext-Heavy"]
        case .arial: ["ArialMT", "ArialMT", "Arial-BoldMT", "Arial-BoldMT", "Arial-BoldMT"]
        case .verdana: ["Verdana", "Verdana", "Verdana-Bold", "Verdana-Bold", "Verdana-Bold"]
        case .gillSans: ["GillSans", "GillSans", "GillSans-SemiBold", "GillSans-Bold", "GillSans-UltraBold"]
        case .futura: ["Futura-Medium", "Futura-Medium", "Futura-Bold", "Futura-Bold", "Futura-Bold"]
        case .georgia: ["Georgia", "Georgia", "Georgia-Bold", "Georgia-Bold", "Georgia-Bold"]
        case .times: ["TimesNewRomanPSMT", "TimesNewRomanPSMT", "TimesNewRomanPS-BoldMT", "TimesNewRomanPS-BoldMT", "TimesNewRomanPS-BoldMT"]
        case .baskerville: ["Baskerville", "Baskerville", "Baskerville-SemiBold", "Baskerville-Bold", "Baskerville-Bold"]
        case .courier: ["CourierNewPSMT", "CourierNewPSMT", "CourierNewPS-BoldMT", "CourierNewPS-BoldMT", "CourierNewPS-BoldMT"]
        }
    }

    func font(size: CGFloat, weight: FontWeightOption) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        if let faces, let font = UIFont(name: faces[weight.index], size: size) {
            return font
        }
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        default: return system
        }
        guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum FontWeightOption: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, heavy

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var uiWeight: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        }
    }

    var symbol: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }

    var swiftUI: SwiftUI.TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

enum MarkerStyle: String, Codable, CaseIterable, Identifiable {
    case none, arrows, line, arrowsAndLine, band

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .arrows: "Arrows"
        case .line: "Line"
        case .arrowsAndLine: "Arrows + Line"
        case .band: "Highlight Band"
        }
    }
}

struct ColorTheme: Identifiable {
    let name: String
    let text: RGBAColor
    let background: RGBAColor
    var id: String { name }

    static let presets: [ColorTheme] = [
        ColorTheme(name: "White on Black", text: .white, background: .black),
        ColorTheme(name: "Black on White", text: .black, background: .white),
        ColorTheme(name: "Yellow on Black", text: RGBAColor(1, 0.86, 0.2), background: .black),
        ColorTheme(name: "Green on Black", text: RGBAColor(0.35, 1, 0.45), background: .black),
        ColorTheme(name: "Cyan on Black", text: RGBAColor(0.4, 0.9, 1), background: .black),
        ColorTheme(name: "White on Navy", text: .white, background: RGBAColor(0.05, 0.1, 0.25)),
    ]
}

struct PrompterSettings: Codable, Equatable {
    // Scrolling
    var speed: Double = 20               // 1...100
    var countdown: Int = 3               // seconds, 0 = off
    var tapToPause = true
    var autoHideControls = true

    // Text
    var fontFamily: FontFamily = .system
    var fontWeight: FontWeightOption = .semibold
    var fontSize: Double = 64            // points
    var lineSpacing: Double = 1.3        // multiple of the font's line height
    var marginPercent: Double = 0.08     // each side, fraction of the screen width
    var alignment: TextAlignmentOption = .leading
    var uppercase = false

    // Colors
    var textColor: RGBAColor = .white
    var backgroundColor: RGBAColor = .black
    var markerColor = RGBAColor(1, 0.35, 0.21)

    // Mirror
    var mirrorHorizontal = false
    var mirrorVertical = false

    // Reading guide
    var markerStyle: MarkerStyle = .arrowsAndLine
    var markerPosition: Double = 0.3     // fraction of the screen height from the top
    var fadeEdges = true

    // Editor
    var autoCleanOnPaste = true
    var wordsPerMinute = 140

    static let speedRange: ClosedRange<Double> = 1...100
    static let fontSizeRange: ClosedRange<Double> = 20...200

    func uiFont(size: CGFloat? = nil) -> UIFont {
        fontFamily.font(size: size ?? CGFloat(fontSize), weight: fontWeight)
    }

    /// Everything that changes how the script text itself is laid out.
    struct TextStyle: Equatable {
        var fontFamily: FontFamily
        var fontWeight: FontWeightOption
        var fontSize: Double
        var lineSpacing: Double
        var alignment: TextAlignmentOption
        var textColor: RGBAColor
        var uppercase: Bool
    }

    var textStyle: TextStyle {
        TextStyle(fontFamily: fontFamily, fontWeight: fontWeight, fontSize: fontSize,
                  lineSpacing: lineSpacing, alignment: alignment, textColor: textColor, uppercase: uppercase)
    }
}

/// Persists `PrompterSettings` in UserDefaults. Settings added in later versions fall back to their defaults.
@MainActor
@Observable
final class SettingsStore {
    var settings: PrompterSettings {
        didSet { save() }
    }

    private static let key = "prompterSettings.v1"

    init() {
        settings = Self.load()
    }

    func reset() {
        settings = PrompterSettings()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func load() -> PrompterSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(PrompterSettings()),
              var merged = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any]
        else { return PrompterSettings() }
        merged.merge(stored) { _, storedValue in storedValue }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(PrompterSettings.self, from: mergedData)
        else { return PrompterSettings() }
        return settings
    }
}
