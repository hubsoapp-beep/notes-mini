import AppKit
import NotesMiniCore

/// The window's content view.
///
/// It reports its current size as its fitting size, which is the one thing that stops AppKit from
/// resizing the window to fit its contents. Auto Layout is a single engine for the whole window, and
/// with nothing pinning the window the engine was free to satisfy the note list's preferred width by
/// narrowing the window — 430 collapsed to 188 the moment the list opened. Pinning the size with
/// required constraints fixed that but made the window impossible to drag: every live resize was
/// answered by an engine that still held the old number. Reporting the size we already have leaves
/// nothing to negotiate and nothing to fight, so the edges drag like any other window.
final class PanelContentView: NSView {
    override var fittingSize: NSSize { bounds.size }
}

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

    /// Pending write of the window frame. See `scheduleFrameSave()`.
    private var frameSaveWork: DispatchWorkItem?

    /// Whether the panel height follows the note. See `Prefs.autoHeight`.
    private var autoHeight = Prefs.autoHeight

    /// Frame to come back to after the green button fills the screen; `nil` when not expanded.
    private var expandedFrom: NSRect?

    /// True while the panel is being moved by this controller, so `windowDidMove` can tell its own
    /// frame changes apart from the person dragging the window.
    private var adjustingFrame = false

    init(store: NoteStore) {
        self.store = store
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: 260))
        super.init()

        card.translatesAutoresizingMaskIntoConstraints = false
        let content = PanelContentView()
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
        panel.contentMinSize = NSSize(width: minWidth, height: minHeight)
        // Dragging is handled by the header, not by the window background: the card, the editor
        // and the footer cover every point of the panel, so there is no background left to grab.
        panel.isMovableByWindowBackground = false

        header.onNewNote = { [weak self] in self?.onRequestNewNote?() }
        header.onBrowse = { [weak self] in self?.onRequestBrowse?() }
        header.onActions = { [weak self] in self?.onRequestActionPanel?() }
        header.onDoubleClick = { [weak self] in self?.toggleAutoHeight() }
        footer.onFormat = { [weak self] in self?.onRequestActionPanel?() }

        configureTrafficLights()

        editorView.onEscape = { [weak self] in self?.escapePressed() }
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
        // A panel put away in the Dock has to come back from it, not just be ordered front.
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        // macOS 14+: when the cooperative activation above loses the race (another app is
        // frontmost and refuses to yield), a canJoinAllSpaces window stays glued to the Space it
        // was created on — ordered "front" somewhere the user is not looking. Tearing the window
        // off the screen and re-ordering it forces the window server to re-join the *current*
        // Space, which is the whole point of showing the panel.
        panel.orderOut(nil)
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
        editorView.dismissEmojiPicker()
        store.flushAll()
        saveFrameNow()
        panel.orderOut(nil)
    }

    // MARK: window chrome

    /// The three lights mean what they mean for this panel, not what they would mean for a document.
    private func configureTrafficLights() {
        let close = panel.standardWindowButton(.closeButton)
        close?.target = self
        close?.action = #selector(closeTapped)

        let miniaturize = panel.standardWindowButton(.miniaturizeButton)
        miniaturize?.target = self
        miniaturize?.action = #selector(miniaturizeTapped)

        let zoom = panel.standardWindowButton(.zoomButton)
        zoom?.target = self
        zoom?.action = #selector(zoomTapped)
        zoom?.toolTip = "Powiększ do pełnego ekranu"
    }

    /// Red: the panel goes away, the app keeps running in the menu bar.
    @objc private func closeTapped() { hide() }

    /// Yellow: to the Dock. `show()` brings it back from there.
    @objc func miniaturizeTapped() { panel.miniaturize(nil) }

    /// Green: the whole screen, edge to edge, with the traffic lights out of the way. A panel that
    /// exists to stay on top of every other window has no business moving to a full-screen Space of
    /// its own, where it would be alone with nothing to be on top of — so this fills the screen it is
    /// already on, over the menu bar and the Dock, and leaves the panel level alone.
    @objc func zoomTapped() {
        if expandedFrom != nil { leaveFullScreen() } else { enterFullScreen() }
    }

    private func enterFullScreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        expandedFrom = panel.frame
        setTrafficLightsHidden(true)
        // Corner to corner there is no window edge to round off; rounded corners here would show the
        // desktop through them, which is exactly what full screen is supposed to hide.
        card.cornerRadius = 0
        adjustingFrame = true
        panel.setFrame(screen.frame, display: true)
        adjustingFrame = false
        scheduleFrameSave()
    }

    private func leaveFullScreen() {
        guard let previous = expandedFrom else { return }
        expandedFrom = nil
        setTrafficLightsHidden(false)
        card.cornerRadius = CardBackgroundView.defaultCornerRadius
        adjustingFrame = true
        panel.setFrame(previous, display: true)
        adjustingFrame = false
        scheduleFrameSave()
    }

    /// Esc leaves the full screen before it hides the panel: the panel is still on screen, so the
    /// smaller step is the one that matches what the person is looking at.
    private func escapePressed() {
        if expandedFrom != nil { leaveFullScreen() } else { hide() }
    }

    private func setTrafficLightsHidden(_ hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// Double-clicking the header puts the height back in the note's hands, or takes it back out.
    private func toggleAutoHeight() {
        autoHeight.toggle()
        Prefs.autoHeight = autoHeight
        if autoHeight { resizeToFitContent() }
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

    /// Shows the list over the note.
    ///
    /// It fills whatever size the panel already has: opening a list is a change of mode, not a
    /// change of window, and resizing here is what made the panel jump every time the list opened.
    func presentOverlay(items: [OverlayItem], placeholder: String, emptyText: String) {
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
        expandedFrom = nil
        setTrafficLightsHidden(false)
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
    ///
    /// Only while the height is still the note's to decide: after a manual resize the size the
    /// person chose wins, and a longer note scrolls instead of pushing the window around.
    private func resizeToFitContent() {
        guard panel.isVisible, autoHeight, expandedFrom == nil else { return }
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
        // Dragging a full-screen panel is a way out of full screen: the person has taken the window
        // somewhere, so the chrome comes back and the window stays where they dropped it.
        if expandedFrom != nil, !adjustingFrame {
            expandedFrom = nil
            setTrafficLightsHidden(false)
        }
        scheduleFrameSave()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleFrameSave()
    }

    /// A finished drag is a decision: this is the size from now on.
    func windowDidEndLiveResize(_ notification: Notification) {
        expandedFrom = nil
        setTrafficLightsHidden(false)
        if autoHeight {
            autoHeight = false
            Prefs.autoHeight = false
        }
        scheduleFrameSave()
    }

    /// Remembers where the panel is, once it has stopped moving.
    ///
    /// A drag fires `windowDidMove` on every mouse-moved event and `resizeToFitContent` fires
    /// `windowDidResize` several times per keystroke; writing to `UserDefaults` for each of those
    /// is a lot of pointless I/O in the middle of the one interaction that has to stay smooth.
    private func scheduleFrameSave() {
        frameSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Prefs.panelFrame = frameToRemember
        }
        frameSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Writes a pending frame without waiting.
    ///
    /// The panel is flushed when it is put away and when the app quits, so a drag followed straight
    /// by Escape or ⌘Q is not lost — hiding does not move the window, so the frame is still the one
    /// the user just chose.
    func saveFrameNow() {
        frameSaveWork?.cancel()
        frameSaveWork = nil
        Prefs.panelFrame = frameToRemember
    }

    /// The frame worth remembering. Filling the screen from the green button is temporary, so the
    /// size to reopen with is the one the panel was expanded from.
    private var frameToRemember: NSRect { expandedFrom ?? panel.frame }
}
