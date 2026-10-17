import AppKit

/// The rounded card that holds the whole panel.
///
/// Two layers: a blur of whatever is behind the transparent window, and a translucent tint on top
/// of it. The tint is what makes the surface readable over arbitrary content — a pure blur over a
/// dark code editor and over a white document would otherwise look like two different apps.
final class CardBackgroundView: NSView {

    private let blur = NSVisualEffectView()
    private let tint = NSView()

    var cornerRadius: CGFloat = 13 {
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

    private func applyShape() {
        let radius = cornerRadius
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        tint.layer?.cornerRadius = radius
        tint.layer?.cornerCurve = .continuous
        tint.layer?.masksToBounds = true
        // Slightly translucent so the blur still reads as a frosted surface, not a flat panel.
        tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(isDark ? 0.86 : 0.90).cgColor
        tint.layer?.borderWidth = 0.75
        tint.layer?.borderColor = (isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.06)).cgColor

        // Clip the blur to the same rounded shape.
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
    }
}
