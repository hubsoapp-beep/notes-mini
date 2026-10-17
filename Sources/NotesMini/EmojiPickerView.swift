import AppKit
import NotesMiniCore

/// The `:` picker: a compact grid of emoji that filters while the user keeps typing.
///
/// It deliberately has **no text field**. The query stays in the note — `:serc` is the markdown
/// being written — and this view only watches that line. Keyboard focus therefore never leaves the
/// editor: there is no hand-off to lose, an input method keeps composing normally, and Escape
/// closes the picker instead of the whole panel.
final class EmojiPickerView: NSView {

    var onPick: ((String) -> Void)?

    private(set) var results: [Emoji] = []
    private var selection = 0
    private var hovered: Int?

    private let columns = 8
    private let cell: CGFloat = 32
    private let sideInset: CGFloat = 12
    private let verticalInset: CGFloat = 10
    private let minRows = 3
    private let maxRows = 6

    /// The picker is driven entirely from outside; it must never take the keyboard away.
    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { true }

    private var rowCount: Int {
        let needed = (results.count + columns - 1) / columns
        return min(max(needed, minRows), maxRows)
    }

    var contentSize: NSSize {
        NSSize(width: sideInset * 2 + CGFloat(columns) * cell,
               height: verticalInset * 2 + CGFloat(rowCount) * cell)
    }

    var isEmpty: Bool { results.isEmpty }

    var currentEmoji: String? {
        selection < results.count ? results[selection].char : nil
    }

    // MARK: contents

    func show(query: String) {
        results = EmojiCatalog.search(query)
        selection = 0
        hovered = nil
        needsDisplay = true
    }

    func moveSelection(dx: Int, dy: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + dx + dy * columns))
        needsDisplay = true
    }

    func pickCurrent() {
        guard let emoji = currentEmoji else { return }
        onPick?(emoji)
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        outline.fill()
        (NSColor(white: 1, alpha: 0.10)).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        guard !results.isEmpty else {
            let text = "Brak wyników" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                      withAttributes: attrs)
            return
        }

        let textAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20)]
        for (index, emoji) in results.enumerated() {
            let rect = cellRect(for: index)
            if index == selection {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
            } else if index == hovered {
                NSColor.labelColor.withAlphaComponent(0.10).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
            }
            let text = emoji.char as NSString
            let size = text.size(withAttributes: textAttrs)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                      withAttributes: textAttrs)
        }
    }

    private func cellRect(for index: Int) -> NSRect {
        let column = index % columns
        let row = index / columns
        return NSRect(x: sideInset + CGFloat(column) * cell,
                      y: verticalInset + CGFloat(row) * cell,
                      width: cell, height: cell)
    }

    private func index(at point: NSPoint) -> Int? {
        let column = Int((point.x - sideInset) / cell)
        let row = Int((point.y - verticalInset) / cell)
        guard column >= 0, column < columns, row >= 0 else { return nil }
        let index = row * columns + column
        return index < results.count ? index : nil
    }

    // MARK: mouse

    // `.activeAlways` matters here: the picker's window is never key, and a plain tracking area
    // would stay silent until the window was activated.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let index = index(at: convert(event.locationInWindow, from: nil))
        guard index != hovered else { return }
        hovered = index
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        selection = index
        needsDisplay = true
        pickCurrent()
    }
}

/// The window that carries the picker.
///
/// A borderless child of the notes panel at the same overlay level, so it floats above other apps
/// and travels with the panel when it is dragged. It never becomes key — the editor below keeps
/// the keyboard for the whole interaction.
final class EmojiPickerPanel: NSPanel {

    let picker = EmojiPickerView()
    private weak var host: NSWindow?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        // Same level as the panel: above full-screen apps, above the menu bar.
        level = WindowLevel.overlay
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = picker
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the grid under the caret, flipping above it when the bottom of the screen is close.
    func present(anchor: NSRect, in parent: NSWindow) {
        if host !== parent {
            host?.removeChildWindow(self)
            parent.addChildWindow(self, ordered: .above)
            host = parent
        }
        let size = picker.contentSize
        var origin = NSPoint(x: anchor.minX - sideInset, y: anchor.minY - 6 - size.height)
        if let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(visible.minX + 4, origin.x), visible.maxX - size.width - 4)
            if origin.y < visible.minY + 4 {
                origin.y = min(anchor.maxY + 6, visible.maxY - size.height - 4)
            }
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFront(nil)
    }

    func dismiss() {
        // Detach rather than only order out: a child window's ordering follows its parent, so
        // `orderOut` alone leaves the grid on screen.
        if let host { host.removeChildWindow(self) }
        host = nil
        orderOut(nil)
    }

    private var sideInset: CGFloat { 12 }
}
