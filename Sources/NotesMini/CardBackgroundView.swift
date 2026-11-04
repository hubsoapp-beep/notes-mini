import AppKit

/// The rounded card that holds the whole panel: one flat, opaque surface with a hairline rim.
///
/// Opaque on purpose. Text stays equally readable over any window behind the panel, and the note list
/// and the action panel can share exactly the same colour.
final class CardBackgroundView: NSView {

    /// The radius the card is drawn with when it is a window rather than the whole screen.
    static let defaultCornerRadius: CGFloat = 17

    private static let darkSurface = NSColor(srgbRed: 0x23 / 255, green: 0x24 / 255, blue: 0x26 / 255, alpha: 1)
    private static let lightSurface = NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF8 / 255, alpha: 1)

    var cornerRadius: CGFloat = CardBackgroundView.defaultCornerRadius {
        didSet { applyShape() }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        applyShape()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyShape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyShape()
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The panel's surface colour, shared with the views that sit on top of the card.
    static func surfaceColor(for appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? darkSurface : lightSurface
    }

    private func applyShape() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = Self.surfaceColor(for: effectiveAppearance).cgColor
        layer.borderWidth = 1
        layer.borderColor = (Self.isDark(effectiveAppearance)
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(white: 0, alpha: 0.09)).cgColor
    }
}
