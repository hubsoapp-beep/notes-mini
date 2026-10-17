import AppKit

/// Launch-at-login through `SMAppService` when available, falling back to a LaunchAgent plist.
///
/// `SMAppService` needs a real signed bundle in /Applications; the LaunchAgent path keeps the
/// option working when the app runs from a build directory.
enum LaunchAtLogin {

    private static var label: String { "pl.milosz.notesmini.launch" }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func set(enabled: Bool) {
        if enabled { install() } else { remove() }
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private static func install() {
        guard let executable = Bundle.main.executableURL else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let url = plistURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: url)
        }
    }

    private static func remove() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
