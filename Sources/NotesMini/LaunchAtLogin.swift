import AppKit

/// The login item, written as a LaunchAgent plist.
///
/// The trade-off is visibility: `SMAppService` would list the app in System Settings → Login
/// Items, where the user can see and revoke it, while a plist in `~/Library/LaunchAgents` is
/// invisible there and can be deleted or left behind by a reinstall. Because of that second half,
/// the stored preference and the plist are reconciled on every launch — see `sync()`.
enum LaunchAtLogin {

    private static var label: String { "pl.milosz.notesmini.launch" }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func set(enabled: Bool) {
        if enabled { install() } else { remove() }
    }

    /// Brings the login item in line with the stored preference.
    ///
    /// The preference is the source of truth: the plist can be deleted by the user or survive a
    /// reinstall pointing at an old build, and neither is visible from the Preferences checkbox.
    /// Reconciling on launch also means the plist always points at the copy that is actually
    /// running, which is the copy the user means.
    static func sync() {
        let wanted = Prefs.launchAtLogin
        if wanted && !isEnabled { install() }
        if !wanted && isEnabled { remove() }
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
