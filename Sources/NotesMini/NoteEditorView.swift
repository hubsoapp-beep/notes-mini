import AppKit
import NotesMiniCore

/// Owns the editor: raw markdown is the source of truth, the rendered attributed string is what
/// the user sees and types into, and every change is translated back to raw.
///
/// Raw ⇄ display translation is diff-based: we compare the previous display string with the new
/// one, get one replaced range, map it back through the renderer's offset table, and apply the
/// edit to the raw markdown. That keeps hidden markers intact and needs no per-keystroke
/// knowledge of markdown syntax.
final class NoteEditorView: NSView, NSTextViewDelegate {

    private let scrollView = NSScrollView()
    let editor: MarkdownEditor
    private let decorationLayout: DecorationLayoutManager

    private(set) var note: Note?
    private var render: NoteRender
    private var lastDisplay = ""
    private var isApplying = false

    private var undoStack: [(raw: String, selection: NSRange)] = []
    private var redoStack: [(raw: String, selection: NSRange)] = []
    private let undoLimit = 300

    var store: NoteStore?
    var onContentChange: ((Note) -> Void)?
    var onEscape: (() -> Void)?
    var onFocusLost: (() -> Void)?

    // MARK: setup

    init() {
        editor = MarkdownEditor.make()
        decorationLayout = editor.layoutManager as! DecorationLayoutManager
        render = NoteRenderer.render("", theme: Prefs.theme)
        super.init(frame: .zero)

        editor.host = self
        editor.delegate = self
        editor.onEscape = { [weak self] in self?.onEscape?() }

        scrollView.documentView = editor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    var isEmpty: Bool { note == nil }
    var currentRender: NoteRender { render }
    var currentRaw: String { note?.body ?? "" }

    /// Height the rendered text needs, used to size the panel to its content.
    var usedContentHeight: CGFloat {
        guard let container = editor.textContainer, let layout = editor.layoutManager else { return 0 }
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height + editor.textContainerInset.height * 2
    }

    // MARK: loading

    func load(_ note: Note, caretAtEnd: Bool = true) {
        self.note = note
        undoStack.removeAll()
        redoStack.removeAll()
        render = NoteRenderer.render(note.body, theme: Prefs.theme)
        let caret = caretAtEnd ? (note.body as NSString).length : 0
        applyRender(caretRaw: caret, length: 0)
    }

    /// Re-render in place, e.g. after the font size or appearance changed.
    func refreshTheme() {
        guard let note else { return }
        let caret = selectedRawRange.location
        let length = selectedRawRange.length
        render = NoteRenderer.render(note.body, theme: Prefs.theme)
        applyRender(caretRaw: caret, length: length)
    }

    func clear() {
        note = nil
        render = NoteRenderer.render("", theme: Prefs.theme)
        applyRender(caretRaw: 0, length: 0)
    }

    // MARK: display ⇄ raw

    private func applyRender(caretRaw: Int, length: Int) {
        isApplying = true
        let display = render.display
        editor.textStorage?.setAttributedString(display)
        decorationLayout.update(render: render, theme: Prefs.theme)
        let start = render.displayOffsetForCaret(caretRaw)
        let end = render.displayOffsetForCaret(caretRaw + length)
        editor.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        editor.typingAttributes = [.font: Prefs.theme.baseFont, .foregroundColor: NSColor.labelColor]
        lastDisplay = display.string
        isApplying = false
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplying, note != nil else { return }
        // While an IME is composing, the marked text is not committed markdown yet. The whole
        // composition arrives as one change once it commits, because we keep `lastDisplay` at
        // its pre-composition value.
        if editor.hasMarkedText() { return }
        commitDisplayChange()
    }

    private func commitDisplayChange() {
        guard let note else { return }
        let newDisplay = editor.string
        guard newDisplay != lastDisplay else { return }
        let (loc, len, inserted) = Self.diff(old: lastDisplay, new: newDisplay)

        let previousRaw = note.body
        let rawRange = render.rawRange(forDisplayRange: NSRange(location: loc, length: len))
        let newRaw = (previousRaw as NSString).replacingCharacters(in: rawRange, with: inserted)
        guard newRaw != previousRaw else { return }

        pushUndo(raw: previousRaw, selection: selectedRawRange)
        let caretRaw = rawRange.location + (inserted as NSString).length
        note.body = newRaw
        store?.scheduleSave(note)
        render = NoteRenderer.render(newRaw, theme: Prefs.theme)
        applyRender(caretRaw: caretRaw, length: 0)
        onContentChange?(note)
    }

    /// One replaced range between two strings: the shared prefix and suffix are trimmed away.
    static func diff(old: String, new: String) -> (location: Int, length: Int, inserted: String) {
        let o = old as NSString
        let n = new as NSString
        let limit = min(o.length, n.length)
        var prefix = 0
        while prefix < limit, o.character(at: prefix) == n.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < (limit - prefix),
              o.character(at: o.length - 1 - suffix) == n.character(at: n.length - 1 - suffix) { suffix += 1 }
        let removed = NSRange(location: prefix, length: o.length - prefix - suffix)
        let inserted = n.substring(with: NSRange(location: prefix, length: n.length - prefix - suffix))
        return (removed.location, removed.length, inserted)
    }

    // MARK: selections

    /// The current display selection mapped into raw markdown offsets.
    var selectedRawRange: NSRange {
        render.rawRange(forDisplayRange: editor.selectedRange())
    }

    private func selectionAnchorRaw() -> Int {
        let display = editor.selectedRange()
        return render.rawRange(forDisplayRange: display).location
    }

    // MARK: undo

    private func pushUndo(raw: String, selection: NSRange) {
        undoStack.append((raw, selection))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @objc func undoAction(_ sender: Any?) {
        guard let note, let entry = undoStack.popLast() else { return }
        redoStack.append((note.body, selectedRawRange))
        applySnapshot(raw: entry.raw, selection: entry.selection)
    }

    @objc func redoAction(_ sender: Any?) {
        guard let note, let entry = redoStack.popLast() else { return }
        undoStack.append((note.body, selectedRawRange))
        applySnapshot(raw: entry.raw, selection: entry.selection)
    }

    private func applySnapshot(raw: String, selection: NSRange) {
        guard let note else { return }
        note.body = raw
        store?.scheduleSave(note)
        render = NoteRenderer.render(raw, theme: Prefs.theme)
        applyRender(caretRaw: selection.location, length: selection.length)
        onContentChange?(note)
    }

    // MARK: edits from the toolbar / shortcuts

    /// Applies an edit computed on raw markdown and puts the caret back sensibly.
    private func applyReplace(_ newRaw: String, caretRaw: Int, length: Int = 0) {
        guard let note else { return }
        guard newRaw != note.body else { return }
        pushUndo(raw: note.body, selection: selectedRawRange)
        note.body = newRaw
        store?.scheduleSave(note)
        render = NoteRenderer.render(newRaw, theme: Prefs.theme)
        applyRender(caretRaw: caretRaw, length: length)
        onContentChange?(note)
    }

    private func toggleInline(_ marker: String) {
        guard let note else { return }
        let sel = selectedRawRange
        let inner = (note.body as NSString).substring(with: sel)
        let newRaw = EditorCommands.toggleInlineMarkers(note.body, selection: sel, marker: marker)
        let caret: Int
        let length: Int
        if inner.isEmpty {
            caret = sel.location + (marker as NSString).length
            length = 0
        } else if newRaw.count < note.body.count {
            caret = max(0, sel.location - (marker as NSString).length)
            length = sel.length
        } else {
            caret = sel.location + (marker as NSString).length
            length = sel.length
        }
        applyReplace(newRaw, caretRaw: caret, length: length)
    }

    @objc func toggleBoldAction(_ sender: Any?) { toggleInline("**") }
    @objc func toggleItalicAction(_ sender: Any?) { toggleInline("*") }
    @objc func toggleStrikeAction(_ sender: Any?) { toggleInline("~~") }
    @objc func toggleCodeAction(_ sender: Any?) { toggleInline("`") }

    @objc func toggleUnderlineAction(_ sender: Any?) {
        guard let note else { return }
        let sel = selectedRawRange
        // Underline has no markdown syntax: it is stored as inline HTML.
        let newRaw = EditorCommands.toggleUnderline(note.body, selection: sel)
        let inner = (note.body as NSString).substring(with: sel)
        let caret = inner.isEmpty ? sel.location + 3 : sel.location + (newRaw.count > note.body.count ? 3 : 0)
        applyReplace(newRaw, caretRaw: caret, length: inner.isEmpty ? 0 : sel.length)
    }

    @objc func insertLinkAction(_ sender: Any?) {
        guard let note, let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Wstaw link"
        alert.informativeText = "Adres URL"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: "Wstaw")
        alert.addButton(withTitle: "Anuluj")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let url = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty else { return }
            let sel = self.selectedRawRange
            let newRaw = EditorCommands.insertLink(note.body, selection: sel, url: url)
            let inner = (note.body as NSString).substring(with: sel)
            let insertion = "[\(inner.isEmpty ? url : inner)](\(url))"
            self.applyReplace(newRaw, caretRaw: sel.location + (insertion as NSString).length)
        }
    }

    enum BlockCommand {
        case heading(Int)
        case bulletList
        case orderedList
        case taskList
        case quote
        case codeBlock
        case none

        var kind: EditorCommands.BlockKind {
            switch self {
            case .heading(let l): return l == 1 ? .heading1 : (l == 2 ? .heading2 : (l == 3 ? .heading3 : .heading4))
            case .bulletList: return .bulletList
            case .orderedList: return .orderedList
            case .taskList: return .taskList
            case .quote: return .blockquote
            case .codeBlock: return .codeBlock
            case .none: return .none
            }
        }
    }

    func applyBlock(_ command: BlockCommand) {
        guard let note else { return }
        let anchor = selectionAnchorRaw()
        let index = LineIndex(note.body)
        let line = index.line(of: anchor)
        let oldLineRange = index.range(ofLine: line)

        // A command that already applies to the line turns it off again, like a toolbar toggle.
        let currentLine = (note.body as NSString).substring(oldLineRange)
        var kind = command.kind
        if kind != .none, EditorCommands.detectKind(currentLine) == kind {
            kind = .none
        }

        let newRaw = EditorCommands.applyBlock(note.body, lineIndex: line, kind: kind)
        guard newRaw != note.body else { return }

        let newIndex = LineIndex(newRaw)
        let targetLine = min(max(0, line), max(0, newIndex.count - 1))
        let newLineRange = newIndex.range(ofLine: targetLine)
        let delta = newLineRange.lowerBound - oldLineRange.lowerBound
        let caret = max(newLineRange.lowerBound, min(anchor + delta, newLineRange.upperBound))
        applyReplace(newRaw, caretRaw: caret)
    }

    @objc func heading1Action(_ sender: Any?) { applyBlock(.heading(1)) }
    @objc func heading2Action(_ sender: Any?) { applyBlock(.heading(2)) }
    @objc func heading3Action(_ sender: Any?) { applyBlock(.heading(3)) }
    @objc func bulletListAction(_ sender: Any?) { applyBlock(.bulletList) }
    @objc func orderedListAction(_ sender: Any?) { applyBlock(.orderedList) }
    @objc func taskListAction(_ sender: Any?) { applyBlock(.taskList) }
    @objc func quoteAction(_ sender: Any?) { applyBlock(.quote) }
    @objc func codeBlockAction(_ sender: Any?) { applyBlock(.codeBlock) }
    @objc func clearFormatAction(_ sender: Any?) { applyBlock(.none) }

    @objc func horizontalRuleAction(_ sender: Any?) {
        guard let note else { return }
        let anchor = selectionAnchorRaw()
        let index = LineIndex(note.body)
        let line = index.line(of: anchor)
        let range = index.range(ofLine: line)
        let ns = note.body as NSString
        let newRaw = ns.substring(to: range.lowerBound) + "---\n" + ns.substring(from: range.upperBound)
        applyReplace(newRaw, caretRaw: range.lowerBound + 4)
    }

    /// Tab / Shift-Tab: nest or unnest the current list item.
    func indentSelection(increase: Bool) {
        guard let note else { return }
        let anchor = selectionAnchorRaw()
        let newRaw = EditorCommands.InputRule.changeIndent(raw: note.body, caret: anchor, increase: increase)
        guard newRaw != note.body else { return }
        let delta = newRaw.utf16.count - note.body.utf16.count
        applyReplace(newRaw, caretRaw: anchor + delta)
    }

    /// Return inside a list continues it; on an empty item it leaves the list.
    func handleReturn() -> Bool {
        guard let note else { return false }
        let caret = selectedRawRange.location
        guard let result = EditorCommands.InputRule.continuation(raw: note.body, caret: caret) else { return false }
        applyReplace(result.raw, caretRaw: result.caret)
        return true
    }

    // MARK: checkboxes

    func toggleCheckbox(atDisplayOffset offset: Int) -> Bool {
        guard let note else { return false }
        let rawOffset = render.rawOffsetForCaret(offset)
        guard let marker = CheckboxImages.taskMarkerRawRange(containingRawOffset: rawOffset, raw: note.body) else { return false }
        let newRaw = EditorCommands.toggleCheckbox(note.body, markerRange: marker)
        pushUndo(raw: note.body, selection: selectedRawRange)
        note.body = newRaw
        store?.scheduleSave(note)
        let caret = selectedRawRange.location
        render = NoteRenderer.render(newRaw, theme: Prefs.theme)
        applyRender(caretRaw: caret, length: 0)
        onContentChange?(note)
        return true
    }

    // MARK: misc actions

    @objc func copyAsMarkdownAction(_ sender: Any?) {
        guard let note else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.body, forType: .string)
    }

    @objc func copyAsPlainTextAction(_ sender: Any?) {
        guard let note else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Exporter.plainText(note.body), forType: .string)
    }

    /// Not every action belongs in the menu bar; this catches the leftovers.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let byChars: [String: () -> Void] = [
            "b": { [weak self] in self?.toggleBoldAction(nil) },
            "i": { [weak self] in self?.toggleItalicAction(nil) },
            "u": { [weak self] in self?.toggleUnderlineAction(nil) },
            "e": { [weak self] in self?.toggleCodeAction(nil) },
            "l": { [weak self] in self?.insertLinkAction(nil) },
        ]
        if option {
            switch key {
            case "1": heading1Action(nil); return true
            case "2": heading2Action(nil); return true
            case "3": heading3Action(nil); return true
            case "c": copyAsMarkdownAction(nil); return true
            default: return false
            }
        }
        if shift {
            switch key {
            case "7": taskListAction(nil); return true
            case "8": bulletListAction(nil); return true
            case "9": codeBlockAction(nil); return true
            case "x": toggleStrikeAction(nil); return true
            default: return false
            }
        }
        if let action = byChars[key] { action(); return true }
        return false
    }

    /// True when the caret sits on an empty line, used to decide whether a slash opens a menu.
    var caretIsOnEmptyLine: Bool {
        let anchor = selectionAnchorRaw()
        let index = LineIndex(currentRaw)
        let range = index.range(ofLine: index.line(of: anchor))
        let line = (currentRaw as NSString).substring(range)
        return line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func focus() {
        window?.makeFirstResponder(editor)
    }
}
