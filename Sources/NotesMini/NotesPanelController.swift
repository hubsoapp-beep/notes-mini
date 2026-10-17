import AppKit
import NotesMiniCore

/// The floating notes window: a rounded card with a small header and the editor underneath.
///
/// It is summoned with the global hotkey, hides on Escape or when it loses focus, and keeps its
/// own frame between launches. Height follows the content so a short note does not sit in a tall
/// empty box.
final class NotesPanelController: NSObject, NSWindowDelegate {

    let panel: FloatingPanel
    let editorView = NoteEditorView()
    private let card = CardBackgroundView()
    private let header = HeaderBarView()
    private let footer = FooterBarView()
    private let overlay = OverlayView()

    private var store: NoteStore

    var onRequestBrowse: (() -> Void)?
    var onRequestActionPanel: (() -> Void)?
    var onRequestNewNote: (() -> Void)?
    var onRequestPreferences: (() -> Void)?

    private let minWidth: CGFloat = 360
    private let defaultWidth: CGFloat = 430
    private let minHeight: CGFloat = 240
    private let maxHeight: CGFloat = 640
    private let headerHeight: CGFloat = 38
    private let footerHeight: CGFloat = 24

    init(store: NoteStore) {
        self.store = store
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: 260))
        super.init()

        card.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            card.topAnchor.constraint(equalTo: content.topAnchor),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        header.translatesAutoresizingMaskIntoConstraints = false
        editorView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)
        card.addSubview(editorView)
        card.addSubview(footer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            editorView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: header.bottomAnchor),
            editorView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: footerHeight),
        ])

        panel.contentView = content
        panel.delegate = self
        panel.isMovableByWindowBackground = false

        header.onNewNote = { [weak self] in self?.onRequestNewNote?() }
        header.onBrowse = { [weak self] in self?.onRequestBrowse?() }
        header.onActions = { [weak self] in self?.onRequestActionPanel?() }
        footer.onFormat = { [weak self] in self?.onRequestActionPanel?() }

        editorView.onEscape = { [weak self] in self?.hide() }
        editorView.onContentChange = { [weak self] note in
            self?.header.title = note.uiTitle
            self?.footer.characterCount = note.body.count
            self?.resizeToFitContent()
        }
        editorView.store = store
    }

    // MARK: content

    func show(_ note: Note, focus: Bool = true) {
        editorView.load(note)
        header.title = note.uiTitle
        footer.characterCount = note.body.count
        restoreFrameIfNeeded()
        panel.appearance = Prefs.nsAppearance
        dismissOverlay()
        activateNotesMini()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if focus { editorView.focus() }
        resizeToFitContent()
        // Text layout needs a real width before the content height means anything, so measure
        // again once AppKit has run the layout pass it was just handed.
        DispatchQueue.main.async { [weak self] in self?.resizeToFitContent() }
        Prefs.lastNotePath = note.url.path
    }

    func hide() {
        guard panel.isVisible else { return }
        store.flushAll()
        panel.orderOut(nil)
    }

    func toggle(_ note: Note) {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show(note)
        }
    }

    func refreshCurrentNote() {
        guard let note = editorView.note else { return }
        header.title = note.uiTitle
        footer.characterCount = note.body.count
    }

    var currentNote: Note? { editorView.note }

    // MARK: overlays (⌘P browse, ⌘K actions)

    var isOverlayVisible: Bool { !overlay.isHidden }

    func presentOverlay(items: [OverlayItem], placeholder: String, emptyText: String, height: CGFloat = 0) {
        if overlay.superview == nil {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: header.bottomAnchor),
                overlay.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
            overlay.onClose = { [weak self] in self?.dismissOverlay() }
        }
        overlay.isHidden = false
        if height > 0 {
            var frame = panel.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            panel.setFrame(frame, display: true)
        }
        overlay.present(items: items, placeholder: placeholder, emptyText: emptyText)
    }

    func dismissOverlay() {
        guard overlay.superview != nil, !overlay.isHidden else { return }
        overlay.isHidden = true
        editorView.focus()
        resizeToFitContent()
    }

    // MARK: geometry

    private func restoreFrameIfNeeded() {
        if let saved = Prefs.panelFrame {
            panel.setFrame(saved, display: false)
        } else {
            positionNearTopCentre()
        }
        clampIntoVisibleScreen()
    }

    private func positionNearTopCentre() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: defaultWidth, height: 300)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 90 // slightly below the menu bar, Raycast-like
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func clampIntoVisibleScreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        // Deliberately based on the full screen frame, not `visibleFrame`: the panel is allowed to
        // sit over the menu bar, which is the whole point of the overlay window level.
        let full = screen.frame
        var frame = panel.frame
        frame.size.width = max(minWidth, min(frame.width, full.width - 20))
        frame.size.height = max(minHeight, min(frame.height, full.height - 20))
        // Always keep at least a corner on the display so the panel can be dragged back.
        let keepVisible: CGFloat = 48
        frame.origin.x = min(max(full.minX - frame.width + keepVisible, frame.origin.x), full.maxX - keepVisible)
        frame.origin.y = min(max(full.minY - frame.height + keepVisible, frame.origin.y), full.maxY - keepVisible)
        panel.setFrame(frame, display: false)
    }

    /// Grows and shrinks with the note, keeping the top edge where it is.
    private func resizeToFitContent() {
        guard panel.isVisible else { return }
        panel.layoutIfNeeded()
        let desired = editorView.usedContentHeight + headerHeight + footerHeight
        let target = min(max(desired.rounded(.up), minHeight), maxHeight)
        guard abs(panel.frame.height - target) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: NSWindowDelegate

    /// The panel deliberately does **not** hide when it loses focus: it is meant to sit above
    /// everything while the user works in another app. Losing focus only forces the pending edits
    /// to disk, so nothing is ever lost while the window is out of sight.
    func windowDidResignKey(_ notification: Notification) {
        store.flushAll()
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible else { return }
        Prefs.panelFrame = panel.frame
    }

    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible else { return }
        Prefs.panelFrame = panel.frame
    }
}
