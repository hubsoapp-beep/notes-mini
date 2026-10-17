import AppKit
import Foundation
import NotesMiniCore

extension Note {
    /// Title as the UI shows it: the first line of the note, with a fallback for empty notes.
    var uiTitle: String {
        let t = title
        return t.isEmpty ? "Nowa notatka" : t
    }
}

/// Brings the app forward so the panel can take keystrokes.
///
/// macOS 14 made activation cooperative: `activate(ignoringOtherApps:)` no longer forces the app
/// in front, and an app may only activate itself when the action that summoned it was aimed at
/// it. A global hotkey counts, but if the attempt loses the race the user's typing goes to
/// whatever was in front instead, so this retries once on the next run loop turn.
func activateNotesMini() {
    if #available(macOS 14.0, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
    guard !NSApp.isActive else { return }
    DispatchQueue.main.async {
        guard !NSApp.isActive else { return }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}

/// The markdown pipeline speaks `Range<Int>` (UTF-16 offsets) while AppKit speaks `NSRange`.
/// These two shims keep the conversion in one place.
extension NSString {
    func substring(_ r: Range<Int>) -> String {
        let lo = max(0, min(r.lowerBound, length))
        let hi = max(lo, min(r.upperBound, length))
        return substring(with: NSRange(location: lo, length: hi - lo))
    }
}

extension Range where Bound == Int {
    var nsRange: NSRange {
        NSRange(location: Swift.max(0, lowerBound), length: Swift.max(0, upperBound - lowerBound))
    }
}
