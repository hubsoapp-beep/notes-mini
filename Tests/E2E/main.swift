// End-to-end checks against the real, running app: real window server, real keystrokes, real
// mouse drags. Needs the Accessibility permission for the terminal running it.
//
//   Scripts/check-e2e.sh
//
// The app is started with its own temporary notes folder through the argument domain, so the
// person's notes are never touched. The mouse is borrowed for a moment and then put back.
import AppKit
import ApplicationServices

guard CommandLine.arguments.count >= 3 else {
    print("usage: e2e <NotesMini binary> <empty temp folder>")
    exit(2)
}
let binary = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
guard AXIsProcessTrusted() else {
    print("SKIP: this terminal has no Accessibility permission")
    exit(2)
}

let mouseHome = CGEvent(source: nil)?.location ?? .zero
var failures = 0
var checks = 0
func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print("\(condition ? "ok  " : "FAIL") \(label)\(condition ? "" : " — \(detail())")")
    if !condition { failures += 1 }
}
func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

let process = Process()
process.executableURL = URL(fileURLWithPath: binary)
process.arguments = ["-notesFolder", folder.path, "-hotkey", "ctrl+opt+/"]
// The app must not inherit stdout: a pipe reading this script's output would wait on it forever.
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
try process.run()
func finish() -> Never {
    process.terminate()
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: mouseHome, mouseButton: .left)?.post(tap: .cghidEventTap)
    print("\(checks - failures)/\(checks) e2e checks passed")
    exit(failures == 0 ? 0 : 1)
}
let pid = process.processIdentifier
let appElement = AXUIElementCreateApplication(pid)

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}
func mainWindow() -> AXUIElement? {
    let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute) ?? []
    return windows.first
}
func frame() -> CGRect {
    guard let window = mainWindow() else { return .zero }
    var origin = CGPoint.zero, size = CGSize.zero
    if let value: AXValue = attribute(window, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &origin) }
    if let value: AXValue = attribute(window, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
    return CGRect(origin: origin, size: size)
}
func findTextArea(_ element: AXUIElement) -> AXUIElement? {
    if let role: String = attribute(element, kAXRoleAttribute), role == kAXTextAreaRole { return element }
    let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
    for child in children { if let found = findTextArea(child) { return found } }
    return nil
}
func editorText() -> String {
    guard let window = mainWindow(), let area = findTextArea(window) else { return "<no editor>" }
    return attribute(area, kAXValueAttribute) ?? "<no value>"
}

let source = CGEventSource(stateID: .privateState)
func type(_ text: String, every interval: TimeInterval = 0.03) {
    for unit in text {
        let scalars = Array(String(unit).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)!
            event.keyboardSetUnicodeString(stringLength: scalars.count, unicodeString: scalars)
            event.flags = []
            event.postToPid(pid)
        }
        pause(interval)
    }
}
func command(_ key: CGKeyCode, flags: CGEventFlags = .maskCommand) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
        event.flags = flags
        event.postToPid(pid)
    }
    pause(0.4)
}
let keyN: CGKeyCode = 45
let keyP: CGKeyCode = 35
let keyEscape: CGKeyCode = 53
let keyReturn: CGKeyCode = 36

func drag(from: CGPoint, to: CGPoint) {
    func post(_ type: CGEventType, _ point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        // Modifiers linger in the HID state after a posted shortcut, and ⌥ makes a resize symmetric.
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, from); pause(0.15)
    post(.leftMouseDown, from); pause(0.1)
    for step in 1...12 {
        let t = CGFloat(step) / 12
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        pause(0.02)
    }
    post(.leftMouseUp, to); pause(0.5)
}
/// Drags the bottom right corner by the given amount and returns the new frame.
@discardableResult
func resize(dx: CGFloat, dy: CGFloat) -> CGRect {
    let f = frame()
    let corner = CGPoint(x: f.maxX, y: f.maxY)
    drag(from: corner, to: CGPoint(x: corner.x + dx, y: corner.y + dy))
    return frame()
}
func expectResize(dx: CGFloat, dy: CGFloat, _ label: String) {
    let before = frame()
    let after = resize(dx: dx, dy: dy)
    check(abs(after.width - before.width - dx) <= 3 && abs(after.height - before.height - dy) <= 3,
          label, "\(before.size) -> \(after.size), asked for \(dx),\(dy)")
    pause(0.8)
    check(abs(frame().height - after.height) < 1 && abs(frame().width - after.width) < 1,
          "\(label): size sticks", "\(after.size) -> \(frame().size)")
}
func diskBodies() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.filter { $0.hasSuffix(".md") }.compactMap { try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
}
func diskHas(_ text: String) -> Bool { diskBodies().contains { $0.contains(text) } }


// Launching can take a while on a busy machine: wait for the window, not for a guessed time.
let launchDeadline = Date().addingTimeInterval(15)
while mainWindow() == nil, Date() < launchDeadline { pause(0.1) }
pause(0.5)

// MARK: - typing with pauses: every pause lets a save and a folder reload go by

check(frame().width > 0, "panel is on screen", "no window")
var expected = ""
for chunk in ["alfa ", "beta ", "gamma ", "delta "] {
    type(chunk)
    expected += chunk
    check(editorText() == expected, "typed \(chunk.debugDescription) is on screen", "editor shows \(editorText().debugDescription)")
    pause(1.3)
    check(editorText() == expected, "text survives the save after \(chunk.debugDescription)", "editor shows \(editorText().debugDescription)")
}
pause(0.6)
check(diskHas(expected), "disk holds all of it", "\(diskBodies())")

// Typing straight through several save and reload cycles, with no quiet moment at all.
type(String(repeating: "x", count: 150), every: 0.04)
expected += String(repeating: "x", count: 150)
pause(1.5)
check(editorText() == expected, "uninterrupted typing keeps every character", "editor shows \(editorText().count), expected \(expected.count)")

// MARK: - resizing the first note

expectResize(dx: 120, dy: 140, "first note grows")
expectResize(dx: -60, dy: -70, "first note shrinks")

// MARK: - a brand new note

command(keyN)
pause(0.8)
check(editorText().isEmpty, "⌘N opens an empty note", "editor shows \(editorText().debugDescription)")
expectResize(dx: 80, dy: 60, "new note grows")
expectResize(dx: -40, dy: -30, "new note shrinks")
type("drugi ")
pause(1.3)
type("tekst")
pause(1.3)
check(editorText() == "drugi tekst", "new note keeps its text across saves", "editor shows \(editorText().debugDescription)")
expectResize(dx: 50, dy: 50, "new note grows after typing")
pause(0.6)
check(diskHas("drugi tekst"), "new note is on disk", "\(diskBodies())")

// MARK: - an edit from outside must reach a clean editor, and must not move the window

let sizeBefore = frame()
if let name = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.first(where: { name in
    (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))?.contains("drugi tekst") == true
}) {
    let url = folder.appendingPathComponent(name)
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try? text.replacingOccurrences(of: "drugi tekst", with: "z zewnatrz").write(to: url, atomically: true, encoding: .utf8)
    pause(1.5)
    check(editorText() == "z zewnatrz", "outside edit reaches a clean editor", "editor shows \(editorText().debugDescription)")
    check(frame() == sizeBefore, "outside edit leaves the window alone", "\(sizeBefore) -> \(frame())")
    type(" i dalej")
    pause(1.3)
    check(editorText() == "z zewnatrz i dalej", "typing continues after outside edit", "editor shows \(editorText().debugDescription)")
}

// MARK: - a note with a body: the title line stops changing, so the file keeps its name

command(keyN)
pause(0.6)
type("Tytul\n")
pause(1.3)
var body = "Tytul\n"
for chunk in ["jeden ", "dwa ", "trzy ", "cztery "] {
    type(chunk)
    body += chunk
    pause(1.3)
    check(editorText() == body, "body text survives the save after \(chunk.debugDescription)", "editor shows \(editorText().debugDescription)")
}
pause(0.6)
check(diskHas(body), "disk holds the whole body", "\(diskBodies().filter { $0.contains("Tytul") })")
// A person pausing just long enough for the save, then carrying on: the moment the store reports
// the write is the moment a stale copy of the note can replace what is in the editor.
for chunk in ["szesc ", "siedem ", "osiem ", "dziewiec ", "dziesiec "] {
    type(chunk, every: 0.01)
    body += chunk
    var worst: String?
    let until = Date().addingTimeInterval(0.62)
    while Date() < until {
        let shown = editorText()
        if shown != body { worst = shown }
        pause(0.02)
    }
    check(worst == nil, "text never flickers away after \(chunk.debugDescription)", "editor showed \(worst?.debugDescription ?? "")")
}
pause(1.2)
check(editorText() == body, "typing around saves keeps every word", "editor shows \(editorText().debugDescription)")
check(diskHas(body), "disk holds every word", "\(diskBodies().filter { $0.contains("Tytul") })")

let sized = frame()
type("piec ")
pause(1.3)
check(frame() == sized, "saving does not move the window", "\(sized) -> \(frame())")

// MARK: - the title line: every save renames the file while the person keeps typing

command(keyN)
pause(0.6)
var titled = ""
for chunk in ["zażółć ", "gęślą ", "jaźń ", "tytuł ", "długi "] {
    type(chunk, every: 0.01)
    titled += chunk
    pause(0.62)
    check(editorText() == titled, "title keeps its text through a rename at \(chunk.debugDescription)", "editor shows \(editorText().debugDescription)")
}
pause(1.0)
check(diskHas(titled), "renamed note holds the whole title", "missing")
check(diskBodies().filter { $0.contains("zażółć") }.count == 1, "renames leave one file", "\(diskBodies().filter { $0.contains("zażółć") }.count) files")

// MARK: - the note list stays in the layout after it closes; a long title must not pin the width

command(keyN)
pause(0.6)
type("To jest bardzo dluga notatka ktorej tytul nie miesci sie w waskim oknie panelu i to nawet szerokim")
pause(1.0)
let beforeList = frame()
command(keyP)
pause(0.5)
check(frame() == beforeList, "opening the list leaves the window alone", "\(beforeList) -> \(frame())")
command(keyEscape, flags: [])
pause(0.5)
check(frame() == beforeList, "closing the list leaves the window alone", "\(beforeList) -> \(frame())")
expectResize(dx: -30, dy: 0, "panel narrows after the list showed a long title")
expectResize(dx: 30, dy: 0, "panel widens after the list showed a long title")

// Picking a note from the list, the other way to open one.
command(keyP)
pause(0.5)
command(keyReturn, flags: [])
pause(0.8)
expectResize(dx: 40, dy: 40, "note opened from the list grows")
expectResize(dx: -40, dy: -40, "note opened from the list shrinks")

// MARK: - typing into a note that came from the folder rather than from ⌘N

// Second line on purpose: the title stays put, so the file keeps its name across saves.
let opened = editorText()
var openedBody = opened + "\nlinia "
type("\nlinia ", every: 0.01)
for chunk in ["raz ", "dwa ", "trzy ", "cztery ", "piec ", "szesc "] {
    pause(0.62)
    type(chunk, every: 0.01)
    openedBody += chunk
    check(editorText() == openedBody, "opened note keeps text at \(chunk.debugDescription)", "editor shows \(editorText().suffix(50).debugDescription)")
}
pause(1.5)
check(editorText() == openedBody, "opened note keeps every word", "editor shows \(editorText().suffix(60).debugDescription)")
check(diskHas(openedBody), "opened note reaches the disk in full", "missing")

// MARK: - a tall note, opened new

command(keyN)
pause(0.6)
let tall = String(repeating: "wiersz\n", count: 60)
type(tall, every: 0.005)
// Keystrokes are queued faster than a person types: wait for the app to work through them.
let tallDeadline = Date().addingTimeInterval(30)
while editorText() != tall, Date() < tallDeadline { pause(0.1) }
check(editorText() == tall, "tall note holds every line", "editor shows \(editorText().count) of \(tall.count)")
pause(1.3)
expectResize(dx: 0, dy: -80, "tall note shrinks")
expectResize(dx: 0, dy: 120, "tall note grows")
type("koniec")
pause(1.3)
check(editorText().hasSuffix("koniec"), "tall note keeps typing", "\(editorText().suffix(30).debugDescription)")

// MARK: - put away and brought back with the global hotkey

command(keyN)
pause(0.6)
command(keyEscape, flags: [])
pause(0.5)
check(mainWindow() == nil || frame().width == 0, "Escape hides the panel", "\(frame())")
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 44, keyDown: down)!
    event.flags = [.maskAlternate, .maskControl]
    event.post(tap: .cghidEventTap)
}
pause(0.8)
check(frame().width > 0, "hotkey brings the panel back", "no window")
expectResize(dx: 60, dy: 60, "panel brought back grows")
expectResize(dx: -60, dy: -60, "panel brought back shrinks")

finish()
