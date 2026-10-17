import AppKit

// An accessory app: no Dock icon, no window at launch, just the floating panel and the menu bar
// item. `NSApplicationMain` is not used because the app is assembled from a SwiftPM executable
// rather than an Xcode target.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
