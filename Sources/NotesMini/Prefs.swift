import AppKit
import NotesMiniCore

/// UserDefaults-backed settings. Everything the app remembers between launches lives here.
enum Prefs {

    private static let defaults = UserDefaults.standard

    enum Key {
        static let folder = "notesFolder"
        static let fontSize = "fontSize"
        static let appearance = "appearance"
        static let lastNote = "lastNotePath"
        static let hotkey = "hotkey"
        static let panelFrame = "panelFrame"
        static let launchAtLogin = "launchAtLogin"
        static let autoHeight = "autoHeight"
    }

    static var notesFolder: URL? {
        get { defaults.string(forKey: Key.folder).map { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: Key.folder) }
    }

    static var fontSize: CGFloat {
        get {
            let v = defaults.double(forKey: Key.fontSize)
            return v <= 0 ? 14 : CGFloat(v)
        }
        set { defaults.set(Double(newValue), forKey: Key.fontSize) }
    }

    /// `system`, `light` or `dark`.
    static var appearance: String {
        get { defaults.string(forKey: Key.appearance) ?? "system" }
        set { defaults.set(newValue, forKey: Key.appearance) }
    }

    static var lastNotePath: String? {
        get { defaults.string(forKey: Key.lastNote) }
        set { defaults.set(newValue, forKey: Key.lastNote) }
    }

    /// Carbon-style shortcut string, e.g. `opt+n`.
    static var hotkey: String {
        get { defaults.string(forKey: Key.hotkey) ?? "opt+n" }
        set { defaults.set(newValue, forKey: Key.hotkey) }
    }

    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// Whether the panel height follows the note.
    ///
    /// Off by default: the panel is a fixed narrow column and the note scrolls inside it. Resizing
    /// the window on every keystroke made the glyphs flicker (transparent window composites
    /// everything on each `setFrame`).
    static var autoHeight: Bool {
        get { defaults.object(forKey: Key.autoHeight) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.autoHeight) }
    }

    static var panelFrame: NSRect? {
        get {
            guard let s = defaults.string(forKey: Key.panelFrame) else { return nil }
            let r = NSRectFromString(s)
            return r.isEmpty ? nil : r
        }
        set { defaults.set(newValue.map(NSStringFromRect), forKey: Key.panelFrame) }
    }

    /// Resolves `appearance` into an `NSAppearance`, `nil` meaning "follow the system".
    static var nsAppearance: NSAppearance? {
        switch appearance {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    static var isDark: Bool {
        switch appearance {
        case "light": return false
        case "dark": return true
        default:
            return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    static var theme: RenderTheme {
        RenderTheme(fontSize: fontSize, isDark: isDark)
    }

    /// Default notes folder: `~/Documents/Notes`.
    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Notes", isDirectory: true)
    }
}
