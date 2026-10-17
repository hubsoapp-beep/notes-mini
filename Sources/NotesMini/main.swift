import AppKit

// Notes Mini — entry point. Replaced by the real app shell in App/Application.swift.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()