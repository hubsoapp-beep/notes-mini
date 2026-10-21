import AppKit
import NotesMiniCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures = 0
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}
let view = NoteEditorView()
view.frame = NSRect(x: 0, y: 0, width: 360, height: 600)
let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = view
window.makeFirstResponder(view.editor)
view.layoutSubtreeIfNeeded()
func load(_ raw: String = "") {
    view.load(Note(url: URL(fileURLWithPath: "/tmp/notesmini-unsaved-editor-check.md"), meta: Frontmatter(), body: raw))
}
func type(_ text: String) {
    for char in text { view.editor.insertText(String(char), replacementRange: view.editor.selectedRange()) }
}
func enter() {
    if !view.handleReturn() { view.editor.insertText("\n", replacementRange: view.editor.selectedRange()) }
}
func key(_ text: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                characters: text, charactersIgnoringModifiers: text,
                                isARepeat: false, keyCode: code)!
    view.editor.keyDown(with: event)
}
load()
key("#", code: 20, flags: .shift)
key("#", code: 20, flags: .shift)
check(view.editor.string == "##", "native keyDown keeps incomplete heading visible")
key(" ", code: 49)
check(view.currentRaw == "## " && view.editor.string.isEmpty, "native Space activates heading exactly once")
key("a", code: 0)
check(view.currentRaw == "## a", "native keyDown retains heading prefix")
key("\r", code: 36)
key("[", code: 33)
key("]", code: 30)
check(view.currentRaw == "## a\n- [ ] ", "native Return and brackets create checkbox")
key("a", code: 0)
key("\r", code: 36)
check(view.currentRaw == "## a\n- [ ] a\n- [ ] ", "native Return continues checkbox")
load()
type("#")
check(view.editor.string == "#", "first hash remains visible")
type("#")
check(view.editor.string == "##", "two hashes remain visible")
type(" ")
check(view.editor.string.isEmpty, "space converts heading and hides prefix")
check((view.editor.typingAttributes[.font] as? NSFont)?.pointSize == Prefs.theme.headingFont(level: 2).pointSize, "empty H2 has heading typing font")
type("Nagłówek")
check(view.currentRaw == "## Nagłówek", "heading text preserves raw marker")
check(view.editor.string == "Nagłówek", "heading content stays rendered")
view.undoAction(nil)
check(view.currentRaw == "## Nagłówe", "undo removes final typed character")
view.redoAction(nil)
check(view.currentRaw == "## Nagłówek", "redo restores character")
enter()
type("Tekst")
check(view.currentRaw == "## Nagłówek\nTekst", "Return leaves heading")

for level in 1...6 {
    load()
    let prefix = String(repeating: "#", count: level)
    type(prefix)
    check(view.editor.string == prefix, "H\(level) waits for space")
    type(" ")
    check(view.editor.string.isEmpty, "H\(level) activates on space")
    view.undoAction(nil)
    check(view.editor.string == prefix, "undo reveals H\(level) prefix")
    view.redoAction(nil)
    type("Tytuł ")
    check(view.editor.string == "Tytuł ", "H\(level) retains text and trailing space")
}
for prefix in ["-", "*", "+", "1."] {
    load()
    type(prefix)
    check(view.editor.string == prefix, "list prefix \(prefix) waits for space")
    type(" ")
    check(view.currentRender.blocks.contains { if case .listItem = $0.kind { return true }; return false }, "list prefix \(prefix) activates on space")
}

for marker in ["[]", "[ ]", "- [ ]", "- []"] {
    load()
    type(marker)
    check(view.currentRaw == "- [ ] ", "\(marker) normalizes task immediately")
    check(view.editor.attributedString().length > 0 && view.editor.attributedString().attribute(.attachment, at: 0, effectiveRange: nil) != nil, "\(marker) renders checkbox")
    type("Zakupy")
    check(view.currentRaw == "- [ ] Zakupy", "\(marker) keeps task while typing")
    enter()
    check(view.currentRaw == "- [ ] Zakupy\n- [ ] ", "Return continues task")
    enter()
    check(view.currentRaw == "- [ ] Zakupy\n", "Return exits empty task")
}
load("- abcdef")
view.editor.setSelectedRange(NSRange(location: 6, length: 0)) // after abc, following bullet + two spaces
enter()
check(view.currentRaw == "- abc\n- def", "Return splits list at caret")
load("abcabc")
view.editor.setSelectedRange(NSRange(location: 0, length: 0))
type("abc")
check(view.editor.selectedRange().location == 3, "repeated text keeps insertion caret")
view.undoAction(nil)
check(view.editor.selectedRange().location == 2, "undo restores pre-edit caret")
load("😀")
type("😁")
check(view.currentRaw == "😀😁", "emoji input preserves UTF-16")
load("- [ ] task")
view.editor.selectAll(nil)
check(view.editor.selectedRange().length == view.editor.string.utf16.count, "select all includes checkbox")
type("replacement")
check(view.currentRaw == "replacement", "replacing all removes hidden formatting")

load("## ")
view.editor.deleteBackward(nil)
check(view.currentRaw == "", "Backspace exits empty heading")
load("- [ ] ")
view.editor.deleteBackward(nil)
check(view.currentRaw == "", "Backspace exits empty checkbox")
load("## Heading")
view.editor.setSelectedRange(NSRange(location: 0, length: 0))
view.editor.deleteBackward(nil)
check(view.currentRaw == "Heading", "Backspace removes heading format before content")
view.undoAction(nil)
check(view.currentRaw == "## Heading", "undo restores removed heading format")
load()
type("[]")
view.undoAction(nil)
check(view.currentRaw == "[", "undo reverses checkbox conversion")
view.redoAction(nil)
check(view.currentRaw == "- [ ] ", "redo restores checkbox conversion")
type("Task")
check(view.toggleCheckbox(atDisplayOffset: 0), "checkbox toggle succeeds")
check(view.currentRaw == "- [x] Task", "checkbox toggle persists checked source")
check(view.toggleCheckbox(atDisplayOffset: 0), "checkbox untoggle succeeds")
check(view.currentRaw == "- [ ] Task", "checkbox untoggle persists unchecked source")

load()
type("- abcdef")
view.editor.setSelectedRange(NSRange(location: 4, length: 2))
enter()
check(view.currentRaw == "- a\ndef", "Return replaces selected list text")
load("```\n")
type("[]")
check(view.currentRaw == "```\n[]", "task shortcut stays literal inside code")
load("Before ")
type("[]")
check(view.currentRaw == "Before []", "task shortcut stays literal inside paragraph")
load()
type(" ")
check(view.editor.string == " ", "space on blank line stays visible")
type(" \n  ")
check(view.editor.string == "  \n  ", "whitespace-only lines stay visible")
load("😀")
view.editor.setSelectedRange(NSRange(location: 0, length: 2))
type("😁")
check(view.currentRaw == "😁", "emoji replacement preserves surrogate pair")
let emojiDiff = NoteEditorView.diff(old: "😀", new: "😁")
check(("😀" as NSString).replacingCharacters(in: NSRange(location: emojiDiff.location, length: emojiDiff.length), with: emojiDiff.inserted) == "😁", "fallback diff keeps Unicode intact")
let unicodeSamples = ["", "a", "aaaa", "😀", "😁", "a😀b", "a😁b", "e\u{301}", "e\u{302}", "👩‍💻", "👨‍💻", "🇵🇱"]
for old in unicodeSamples {
    for new in unicodeSamples {
        let change = NoteEditorView.diff(old: old, new: new)
        check((old as NSString).replacingCharacters(in: NSRange(location: change.location, length: change.length), with: change.inserted) == new, "Unicode diff round trip \(old.debugDescription) / \(new.debugDescription)")
    }
}
load("abc")
view.editor.setSelectedRange(NSRange(location: 1, length: 1))
type("X")
view.undoAction(nil)
check(view.currentRaw == "abc" && view.editor.selectedRange() == NSRange(location: 1, length: 1), "undo restores replaced selection")

// A single character must not replace or restyle all existing paragraphs.
load("## Heading\n\n- [ ] First\n- [x] Second\n\nFinal line")
var editedSpan = 0
let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: view.editor.textStorage, queue: nil) { notification in
    if let storage = notification.object as? NSTextStorage { editedSpan = max(editedSpan, storage.editedRange.length) }
}
type("x")
NotificationCenter.default.removeObserver(observer)
check(editedSpan <= 2, "typing invalidates only changed text (actual span \(editedSpan))")

load("first\nsecond")
view.editor.setSelectedRange(NSRange(location: 2, length: 0))
view.heading2Action(nil)
check(view.currentRaw == "## first\nsecond", "format command preserves following line")
load("Before ")
view.editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.editor.selectedRange())
check(view.currentRaw == "Before ", "IME composition does not save provisional text")
view.editor.insertText("日本", replacementRange: view.editor.markedRange())
check(view.currentRaw == "Before 日本", "IME commit preserves complete text")
view.undoAction(nil)
check(view.currentRaw == "Before ", "IME composition undoes as one edit")

load(String(repeating: "## Heading\n\nText with **bold**.\n\n- [ ] task\n\n", count: 20))
let start = Date()
for _ in 0..<50 {
    type("a")
    _ = view.usedContentHeight
}
let typingMillis = Date().timeIntervalSince(start) * 1000 / 50
print(String(format: "Editor typing + layout: %.2f ms/character (%.1f KB note)", typingMillis, Double(view.currentRaw.utf16.count) / 1024))
check(typingMillis < 16.7, "normal-note typing and layout fit one 60 Hz frame on average")
print("\(checks - failures)/\(checks) editor checks passed")
exit(failures == 0 ? 0 : 1)
