import AppKit

/// The slim bar above the editor: current note title on the left, actions on the right.
final class HeaderBarView: NSView {

    var onNewNote: (() -> Void)?
    var onBrowse: (() -> Void)?
    var onActions: (() -> Void)?

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
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),

            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

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
