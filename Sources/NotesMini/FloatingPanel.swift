import AppKit

/// Window level used by the notes panel.
///
/// 102 is `kCGOverlayWindowLevel`: above the menu bar (24), the status bar (25) and pop-up menus
/// (101), below help tags (200) and the screen saver (1000). It is the highest level that still
/// behaves like a normal window, which is exactly what "always visible, even over full-screen
/// apps and the menu bar" needs.
enum WindowLevel {
    static let overlay = NSWindow.Level(rawValue: 102)
}

/// Floating panel with a real title bar: traffic lights in the corner, resizable edges, and the
/// card drawn through the whole window because the title bar itself is transparent.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // `.titled` is what brings the three traffic lights and edge resizing; the title bar is
            // made transparent below so the card still fills the window and the buttons simply sit
            // on top of it. `.nonactivatingPanel` keeps typing from pulling the app forward.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // A panel is a floating window by default, and `isFloatingPanel` resets `level` to
        // `.floating` (3) — so the level must be assigned *after* it.
        isFloatingPanel = true

        level = WindowLevel.overlay
        // Join other applications' sets and full-screen Spaces as a floating overlay.
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        // No title bar chrome, but keep the standard behaviours that matter for typing.
        isRestorable = false

        // The title bar is only a home for the buttons; the window's own title is never shown.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        title = ""
        standardWindowButton(.zoomButton)?.isEnabled = true
    }

    /// The panel must be able to take keyboard focus without activating the app, so typing in
    /// the editor never yanks the user out of the full-screen app underneath.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The panel is allowed to sit over the menu bar — that is the whole point of its window level —
    /// so AppKit's habit of keeping a title bar clear of the menu bar is exactly what stops the green
    /// button from covering the screen. Staying on the display is still enforced, by the controller's
    /// own clamp, which keeps a corner of the panel reachable.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
