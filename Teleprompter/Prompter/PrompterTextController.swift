import SwiftUI
import UIKit

/// SwiftUI wrapper around the UIKit text surface.
struct PrompterSurface: UIViewControllerRepresentable {
    let text: String
    let settings: PrompterSettings
    let engine: PrompterEngine
    /// False while a popover is open, so the popover keeps keyboard focus.
    let keyFocusEnabled: Bool
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> PrompterTextController {
        let controller = PrompterTextController(engine: engine)
        controller.onTap = onTap
        controller.update(text: text, settings: settings)
        return controller
    }

    func updateUIViewController(_ controller: PrompterTextController, context: Context) {
        controller.onTap = onTap
        controller.update(text: text, settings: settings)
        if keyFocusEnabled { controller.reclaimKeyFocus() }
    }
}

/// Renders the script in a TextKit 1 text view (exact content height, tiled drawing for long scripts),
/// applies mirroring, the reading guide and edge fade, and turns hardware keys into engine commands.
final class PrompterTextController: UIViewController, UITextViewDelegate {
    var onTap: (() -> Void)?

    private let engine: PrompterEngine
    private let container = UIView()      // gets the mirror transform
    private let textHolder = UIView()     // carries the fade mask (a mask on the scroll view would scroll with it)
    private let textView = UITextView(usingTextLayoutManager: false)
    private let markerView = MarkerView()
    private let fadeMask = CAGradientLayer()

    private var text = ""
    private var settings = PrompterSettings()
    private var appliedText: String?
    private var appliedStyle: PrompterSettings.TextStyle?
    private var appliedLayout: LayoutKey?
    private var markerY: CGFloat = 0

    private struct LayoutKey: Equatable {
        var size: CGSize
        var margin: Double
        var markerPosition: Double
    }

    init(engine: PrompterEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        view.addSubview(container)
        container.addSubview(textHolder)
        textHolder.addSubview(textView)
        container.addSubview(markerView)

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.delegate = self
        textView.accessibilityIdentifier = "prompterText"

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        textView.addGestureRecognizer(tap)

        markerView.isUserInteractionEnabled = false

        fadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fadeMask.locations = [0, 0.12, 0.86, 1]

        engine.scrollView = textView
        engine.anchorProvider = { [weak self] in self?.anchorAtMarker() }
        engine.offsetForAnchor = { [weak self] index, delta in self?.contentOffset(forCharacter: index, delta: delta) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyIfPossible()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    func update(text: String, settings: PrompterSettings) {
        self.text = text
        self.settings = settings
        applyIfPossible()
    }

    func reclaimKeyFocus() {
        guard view.window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    // MARK: - Applying settings

    private func applyIfPossible() {
        guard isViewLoaded else { return }
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let background = settings.backgroundColor.uiColor
        if container.backgroundColor != background { container.backgroundColor = background }

        let transform = CGAffineTransform(scaleX: settings.mirrorHorizontal ? -1 : 1,
                                          y: settings.mirrorVertical ? -1 : 1)
        if container.transform != transform { container.transform = transform }

        let mask: CALayer? = settings.fadeEdges ? fadeMask : nil
        if textHolder.layer.mask !== mask { textHolder.layer.mask = mask }

        let textChanged = appliedText != text || appliedStyle != settings.textStyle
        let layout = LayoutKey(size: size, margin: settings.marginPercent, markerPosition: settings.markerPosition)
        if textChanged || layout != appliedLayout {
            engine.preservingProgress {
                // The container may be mirrored, so it is placed with bounds + center rather than frame.
                container.bounds = CGRect(origin: .zero, size: size)
                container.center = CGPoint(x: size.width / 2, y: size.height / 2)
                textHolder.frame = container.bounds
                textView.frame = textHolder.bounds
                markerView.frame = container.bounds
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                fadeMask.frame = textHolder.bounds
                CATransaction.commit()

                if textChanged {
                    textView.attributedText = makeAttributedText()
                    appliedText = text
                    appliedStyle = settings.textStyle
                }
                applyInsets()
                textView.layoutManager.ensureLayout(for: textView.textContainer)
                textView.layoutIfNeeded()
            }
            appliedLayout = layout
            engine.viewSize = size
        }

        let font = settings.uiFont()
        markerView.configure(style: settings.markerStyle,
                             y: markerY,
                             bandHeight: font.lineHeight * max(1, settings.lineSpacing),
                             lineColor: settings.textColor.uiColor,
                             arrowColor: settings.markerColor.uiColor)
    }

    private func makeAttributedText() -> NSAttributedString {
        let font = settings.uiFont()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = settings.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping
        if settings.lineSpacing >= 1 {
            paragraph.lineSpacing = (settings.lineSpacing - 1) * font.lineHeight
        } else {
            paragraph.lineHeightMultiple = settings.lineSpacing
        }
        paragraph.paragraphSpacing = font.pointSize * 0.25

        return NSAttributedString(string: Self.displayText(text, settings: settings), attributes: [
            .font: font,
            .foregroundColor: settings.textColor.uiColor,
            .paragraphStyle: paragraph,
        ])
    }

    /// Exactly the string shown on screen (the web remote preview uses the same one, so character positions match).
    static func displayText(_ text: String, settings: PrompterSettings) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "This script is empty." : text
        return settings.uppercase ? body.uppercased() : body
    }

    // MARK: - Positions for the web remote

    func anchorAtMarker() -> (index: Int, delta: Double)? {
        guard textView.textStorage.length > 0 else { return nil }
        let layoutManager = textView.layoutManager
        let markerInText = textView.contentOffset.y + markerY - textView.textContainerInset.top
        let glyph = layoutManager.glyphIndex(for: CGPoint(x: 1, y: max(0, markerInText)), in: textView.textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let center = line.minY + settings.uiFont().lineHeight / 2
        let pitch = max(1, engine.linePitch)
        return (layoutManager.characterIndexForGlyph(at: glyph), Double((markerInText - center) / pitch))
    }

    func contentOffset(forCharacter index: Int, delta: Double) -> CGFloat? {
        let length = textView.textStorage.length
        guard length > 0 else { return nil }
        let layoutManager = textView.layoutManager
        let glyph = layoutManager.glyphIndexForCharacter(at: min(max(index, 0), length - 1))
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let center = line.minY + textView.textContainerInset.top + settings.uiFont().lineHeight / 2
        return center + CGFloat(delta) * engine.linePitch - markerY
    }

    /// The first line starts centred on the reading guide, and the last line can scroll up to it.
    private func applyInsets() {
        let width = textView.bounds.width
        let height = textView.bounds.height
        let font = settings.uiFont()
        let half = font.lineHeight / 2
        markerY = (height * settings.markerPosition).rounded()

        let margin = (width * settings.marginPercent).rounded()
        textView.textContainerInset = UIEdgeInsets(top: 0, left: margin, bottom: 0, right: margin)
        textView.contentInset = UIEdgeInsets(top: max(0, markerY - half), left: 0,
                                             bottom: max(0, height - markerY - half), right: 0)
        engine.linePitch = font.lineHeight * max(1, settings.lineSpacing)
    }

    // MARK: - Touch

    @objc private func handleTap() {
        onTap?()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        engine.userScrollBegan()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isTracking || scrollView.isDecelerating {
            engine.userScrolled(to: scrollView.contentOffset.y)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            engine.userScrolled(to: scrollView.contentOffset.y)
            engine.userScrollEnded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        engine.userScrolled(to: scrollView.contentOffset.y)
        engine.userScrollEnded()
    }

    // MARK: - Keyboard and Bluetooth remotes

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        func command(_ title: String, _ input: String, _ action: Selector) -> UIKeyCommand {
            let c = UIKeyCommand(title: title, action: action, input: input)
            c.wantsPriorityOverSystemBehavior = true
            return c
        }
        return [
            command("Play / Pause", " ", #selector(keyToggle)),
            command("Play / Pause (Return)", "\r", #selector(keyToggle)),
            command("Faster", UIKeyCommand.inputRightArrow, #selector(keyFaster)),
            command("Slower", UIKeyCommand.inputLeftArrow, #selector(keySlower)),
            command("Scroll Back a Line", UIKeyCommand.inputUpArrow, #selector(keyLineBack)),
            command("Scroll Forward a Line", UIKeyCommand.inputDownArrow, #selector(keyLineForward)),
            command("Page Back", UIKeyCommand.inputPageUp, #selector(keyPageBack)),
            command("Page Forward", UIKeyCommand.inputPageDown, #selector(keyPageForward)),
            command("Back to Top", UIKeyCommand.inputHome, #selector(keyRewind)),
            command("Bigger Text", "=", #selector(keyBigger)),
            command("Smaller Text", "-", #selector(keySmaller)),
            command("Mirror", "m", #selector(keyMirror)),
            command("Close", UIKeyCommand.inputEscape, #selector(keyClose)),
        ]
    }

    @objc private func keyToggle() { engine.togglePlay() }
    @objc private func keyFaster() { engine.adjustSpeed(by: 1) }
    @objc private func keySlower() { engine.adjustSpeed(by: -1) }
    @objc private func keyLineBack() { engine.nudge(lines: -1) }
    @objc private func keyLineForward() { engine.nudge(lines: 1) }
    @objc private func keyPageBack() { engine.page(-1) }
    @objc private func keyPageForward() { engine.page(1) }
    @objc private func keyRewind() { engine.rewind() }
    @objc private func keyBigger() { engine.adjustFontSize(by: 4) }
    @objc private func keySmaller() { engine.adjustFontSize(by: -4) }
    @objc private func keyMirror() { engine.toggleMirror() }
    @objc private func keyClose() { engine.requestExit() }
}

/// Draws the reading guide: arrows at both edges, a line, or a soft highlight band.
final class MarkerView: UIView {
    private var style: MarkerStyle = .none
    private var y: CGFloat = 0
    private var bandHeight: CGFloat = 0
    private var lineColor: UIColor = .white
    private var arrowColor: UIColor = .red

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(style: MarkerStyle, y: CGFloat, bandHeight: CGFloat, lineColor: UIColor, arrowColor: UIColor) {
        guard style != self.style || y != self.y || bandHeight != self.bandHeight
                || lineColor != self.lineColor || arrowColor != self.arrowColor else { return }
        self.style = style
        self.y = y
        self.bandHeight = bandHeight
        self.lineColor = lineColor
        self.arrowColor = arrowColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let w = bounds.width
        switch style {
        case .none:
            return
        case .band:
            lineColor.withAlphaComponent(0.14).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: y - bandHeight / 2, width: w, height: bandHeight)).fill()
        case .line, .arrows, .arrowsAndLine:
            if style != .arrows {
                lineColor.withAlphaComponent(0.3).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: y - 1, width: w, height: 2)).fill()
            }
            if style != .line {
                let size: CGFloat = 26
                arrowColor.setFill()
                let left = UIBezierPath()
                left.move(to: CGPoint(x: 6, y: y - size))
                left.addLine(to: CGPoint(x: 6 + size * 1.2, y: y))
                left.addLine(to: CGPoint(x: 6, y: y + size))
                left.close()
                left.fill()
                let right = UIBezierPath()
                right.move(to: CGPoint(x: w - 6, y: y - size))
                right.addLine(to: CGPoint(x: w - 6 - size * 1.2, y: y))
                right.addLine(to: CGPoint(x: w - 6, y: y + size))
                right.close()
                right.fill()
            }
        }
    }
}
