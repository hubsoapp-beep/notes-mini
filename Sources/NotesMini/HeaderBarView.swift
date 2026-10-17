import AppKit

/// The slim bar above the editor: current note title on the left, actions on the right.
final class HeaderBarView: NSView {

    var onNewNote: (() -> Void)?
    var onBrowse: (() -> Void)?
    var onActions: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    var title: String = "" {
        didSet { titleLabel.stringValue = title }
    }

    private let titleLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .center
        // Raycast centres the note title in its window bar, so it has to be the view that gives way
        // when it grows too long for the space between the edges and the buttons.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let newButton = makeButton("square.and.pencil", tooltip: "Nowa notatka (⌘N)", action: #selector(newTapped))
        let browseButton = makeButton("list.bullet.rectangle", tooltip: "Przeglądaj notatki (⌘P)", action: #selector(browseTapped))
        let actionsButton = makeButton("ellipsis", tooltip: "Akcje (⌘K)", action: #selector(actionsTapped))
        let buttons = NSStackView(views: [newButton, browseButton, actionsButton])
        buttons.orientation = .horizontal
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The traffic lights sit at the left end of this strip, so the title has to start to
            // their right: sharing the corner with them would put text under the buttons.
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 78),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),

            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            // A separator with no height of its own is an unconstrained box: it settles at 5pt and
            // is drawn slightly outside the bar.
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { nil }

    // MARK: dragging the panel

    /// The header doubles as the window's drag handle.
    ///
    /// The panel cannot be moved by its background, because the card, the editor and the footer
    /// cover every point of it, and the editor has to keep its own mouse handling for caret
    /// placement and selection. The header is the one strip that is pure chrome, so it is where a
    /// drag belongs — the same place a title bar would be.
    ///
    /// `hitTest` is what makes that work. The title label sits in the middle of the strip, and a
    /// text field would otherwise swallow the click before it ever reached `mouseDown`; reporting
    /// the header for everything that is not a button turns the whole strip into one surface.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isInsideButton ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        // Double-click hands the height back to the note, or takes it back out. With a real title
        // bar this gesture would zoom the window; here the panel has its own meaning for it.
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        // `performDrag` runs its own tracking loop, so no `mouseDragged` handling is needed here.
        window?.performDrag(with: event)
    }

    private func makeButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    @objc private func newTapped() { onNewNote?() }
    @objc private func browseTapped() { onBrowse?() }
    @objc private func actionsTapped() { onActions?() }
}

private extension NSView {
    /// True when this view, or anything above it, is a button.
    ///
    /// Used to tell "the user pressed a header button" apart from "the user grabbed the strip" —
    /// a button's own subviews must not be mistaken for the drag surface.
    var isInsideButton: Bool {
        var current: NSView? = self
        while let view = current {
            if view is NSButton { return true }
            current = view.superview
        }
        return false
    }
}
