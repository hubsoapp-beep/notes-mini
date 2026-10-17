import AppKit
import NotesMiniCore

/// The slim strip under the editor: character count centred, formatting entry point on the right.
/// Raycast puts the same bar at the bottom of its notes window.
final class FooterBarView: NSView {

    var onFormat: (() -> Void)?

    /// Character count of the current note body. `nil` shows nothing.
    var characterCount: Int? {
        didSet {
            guard characterCount != oldValue else { return }
            countLabel.stringValue = characterCount.map(CountText.characters) ?? ""
        }
    }

    private let countLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)

        countLabel.font = .systemFont(ofSize: 10.5)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        let formatButton = NSButton()
        formatButton.isBordered = false
        formatButton.bezelStyle = .inline
        formatButton.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Formatowanie")
        formatButton.imagePosition = .imageOnly
        formatButton.contentTintColor = .tertiaryLabelColor
        formatButton.toolTip = "Formatowanie i akcje (⌘K)"
        formatButton.target = self
        formatButton.action = #selector(formatTapped)
        formatButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            formatButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            formatButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            formatButton.widthAnchor.constraint(equalToConstant: 24),
            formatButton.heightAnchor.constraint(equalToConstant: 20),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func formatTapped() { onFormat?() }
}
