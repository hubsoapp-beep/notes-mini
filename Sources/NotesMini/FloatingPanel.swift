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

/// Borderless, non-activating panel that floats above everything, on every Space.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // A panel is a floating window by default, and `isFloatingPanel` resets `level` to
        // `.floating` (3) — so the level must be assigned *after* it.
        isFloatingPanel = true

        level = WindowLevel.overlay
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        // No title bar chrome, but keep the standard behaviours that matter for typing.
        isRestorable = false
    }

    /// The panel must be able to take keyboard focus without activating the app, so typing in
    /// the editor never yanks the user out of the full-screen app underneath.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
