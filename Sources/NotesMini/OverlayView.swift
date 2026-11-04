import AppKit

import NotesMiniCore

/// One selectable line in an overlay.
struct OverlayItem {
    let title: String
    let subtitle: String?
    let symbol: String
    let accessory: String?
    let action: () -> Void

    init(title: String, subtitle: String? = nil, symbol: String = "doc.text",
         accessory: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = accessory
        self.action = action
    }
}

/// A single row: icon, title, optional trailing hint. Highlights when it is the current selection.
final class OverlayRowView: NSView {

    var onPick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let accessory = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(item: OverlayItem) {
        super.init(frame: .zero)

        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        title.stringValue = item.title
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        // A note title can be a whole first paragraph. Auto Layout is one engine for the whole window
        // and window size loses to the default resistance, so a label that refuses to truncate pushes
        // the window out to its full text width and then holds it there.
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false

        accessory.stringValue = item.accessory ?? ""
        accessory.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        accessory.textColor = .tertiaryLabelColor
        accessory.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(title)
        addSubview(accessory)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessory.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            accessory.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 6, dy: 1)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onPick?()
    }
}

/// Document view for the note list.
///
/// Flipped, so the rows start at the top: a non-flipped document view is measured from the bottom,
/// and with a panel taller than the list the rows floated at the bottom with empty space above.
final class ListContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Searchable list used for both ⌘P (browse notes) and ⌘K (actions).
/// The search field keeps focus; arrow keys and Return are forwarded here.
final class OverlayView: NSView, NSTextFieldDelegate {

    var onClose: (() -> Void)?

    private let field = NSTextField()
    private let scroll = NSScrollView()
    private let list = NSStackView()
    private let listContainer = ListContainer()
    private let empty = NSTextField(labelWithString: "")

    private var allItems: [OverlayItem] = []
    private var visible: [OverlayItem] = []
    private var rows: [OverlayRowView] = []
    private var selection = 0

    override var isFlipped: Bool { true }

    var query: String { field.stringValue }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        applyBackground()

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = "Szukaj…"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        list.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(list)

        scroll.documentView = listContainer
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .tertiaryLabelColor
        empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false

        addSubview(field)
        addSubview(separator)
        addSubview(scroll)
        addSubview(empty)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            field.heightAnchor.constraint(equalToConstant: 24),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 11),
            // The rule needs its own height: without it the separator and the list below are two
            // unknowns sharing one equation, and Auto Layout is entitled to hand the separator the
            // whole panel — which it did, drawing it as a 555pt vertical line through the middle.
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            list.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            list.topAnchor.constraint(equalTo: listContainer.topAnchor),
            list.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            listContainer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 26),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Covers the note with the card's own colour, so the list reads as the same surface.
    private func applyBackground() {
        layer?.backgroundColor = CardBackgroundView.surfaceColor(for: effectiveAppearance).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    // MARK: presenting

    func present(items: [OverlayItem], placeholder: String, emptyText: String) {
        allItems = items
        field.placeholderString = placeholder
        empty.stringValue = emptyText
        field.stringValue = ""
        selection = 0
        rebuild()
        window?.makeFirstResponder(field)
    }

    /// Hidden views keep their constraints, so a closed list must not leave its rows in the layout.
    func clear() {
        allItems = []
        visible = []
        for row in rows { row.removeFromSuperview() }
        rows.removeAll()
    }

    private func rebuild() {
        for row in rows { row.removeFromSuperview() }
        rows.removeAll()

        let needle = NoteStore.fold(field.stringValue.trimmingCharacters(in: .whitespaces))
        visible = needle.isEmpty ? allItems : allItems.filter {
            NoteStore.fold($0.title).contains(needle) || NoteStore.fold($0.subtitle ?? "").contains(needle)
        }
        if selection >= visible.count { selection = max(0, visible.count - 1) }

        for (index, item) in visible.enumerated() {
            let row = OverlayRowView(item: item)
            row.isSelected = index == selection
            row.onPick = { [weak self] in
                guard let self else { return }
                self.selection = index
                self.chooseCurrent()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            list.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 6),
                row.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -6),
            ])
            rows.append(row)
        }
        empty.isHidden = !visible.isEmpty
        scrollToSelection()
    }

    private func scrollToSelection() {
        guard selection < rows.count else { return }
        rows[selection].scrollToVisible(rows[selection].bounds)
    }

    private func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selection = max(0, min(visible.count - 1, selection + delta))
        for (index, row) in rows.enumerated() { row.isSelected = index == selection }
        scrollToSelection()
    }

    private func chooseCurrent() {
        guard selection < visible.count else { return }
        let action = visible[selection].action
        action()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        selection = 0
        rebuild()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            chooseCurrent(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?(); return true
        default:
            return false
        }
    }
}
