import AppKit

/// The rounded card that holds the whole panel.
///
/// Built the way a sheet of glass reads: a blur of whatever is behind the transparent window, a
/// translucent tint over it, and lighting. The tint is what makes the surface readable over
/// arbitrary content — a pure blur over a dark code editor and over a white document would
/// otherwise look like two different apps. The lighting is what makes it read as glass rather than
/// as a grey box: a bright specular edge along the top, a soft shade settling at the bottom, and a
/// hairline rim that catches the border.
///
/// macOS 26 draws this natively with `NSGlassEffectView`; this target still runs on 14, so the
/// material is approximated from what every supported system has.
final class CardBackgroundView: NSView {

    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let topSheen = CAGradientLayer()
    private let bottomShade = CAGradientLayer()

    /// The radius the card is drawn with when it is a window rather than the whole screen.
    static let defaultCornerRadius: CGFloat = 17

    var cornerRadius: CGFloat = CardBackgroundView.defaultCornerRadius {
        didSet { applyShape() }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        blur.material = .popover
        blur.blendingMode = .behindWindow
        // An always-on-top panel must not dim when it loses focus; that reads as broken.
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)

        // Added after the tint but before any content, so the lighting sits over the material and
        // under the note without having to know about it.
        for gradient in [topSheen, bottomShade] {
            gradient.startPoint = CGPoint(x: 0.5, y: 1)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(gradient)
        }

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyShape()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // Layer coordinates here run bottom-up, so the sheen lives at the top of the card.
        topSheen.frame = CGRect(x: 0, y: bounds.height - 46, width: bounds.width, height: 46)
        bottomShade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 24)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyShape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyShape()
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The translucent tint the card is drawn with.
    ///
    /// Shared with the note list and the action panel, which sit on top of the card and draw their
    /// own surface with it. Kept in one place so the two never drift apart into slightly different
    /// greys, and resolved against the appearance at the moment of use rather than captured once.
    ///
    /// Slightly translucent so the blur still reads as a frosted surface, not a flat panel.
    static func tintColor(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.windowBackgroundColor.withAlphaComponent(isDark ? 0.76 : 0.82)
    }

    private func applyShape() {
        let radius = cornerRadius
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        tint.layer?.cornerRadius = radius
        tint.layer?.cornerCurve = .continuous
        tint.layer?.masksToBounds = true
        tint.layer?.backgroundColor = Self.tintColor(for: effectiveAppearance).cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = (isDark ? NSColor(white: 1, alpha: 0.20) : NSColor(white: 0, alpha: 0.09)).cgColor

        // Clip the blur to the same rounded shape.
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

        applyLighting()
    }

    /// The two gradients that give the surface its direction of light.
    private func applyLighting() {
        let sheen = isDark ? NSColor(white: 1, alpha: 0.24) : NSColor(white: 1, alpha: 0.75)
        let shade = isDark ? NSColor(white: 0, alpha: 0.22) : NSColor(white: 0, alpha: 0.09)

        topSheen.colors = [sheen.cgColor, sheen.withAlphaComponent(0).cgColor]
        // The bright edge is narrow and the fade is quick, like a rim rather than a wash.
        topSheen.locations = [0, 0.45]

        bottomShade.colors = [shade.withAlphaComponent(0).cgColor, shade.cgColor]
        bottomShade.locations = [0.4, 1]
    }
}
