import AppKit
import NotesMiniCore

/// Owns the editor: raw markdown is the source of truth, the rendered attributed string is what
/// the user sees and types into, and every change is translated back to raw.
///
/// AppKit's replacement range is mapped through the renderer's offset table to edit raw Markdown.
/// A Unicode-safe diff handles committed IME composition when no single replacement is available.
final class NoteEditorView: NSView, NSTextViewDelegate {

    private let scrollView = NSScrollView()
    let editor: MarkdownEditor
    private let decorationLayout: DecorationLayoutManager

    private(set) var note: Note?
    private var render: NoteRender
    private var lastDisplay = ""
    private var isApplying = false
    private var pendingEdit: (range: NSRange, text: String, selection: NSRange)?

    private var undoStack: [(raw: String, selection: NSRange)] = []
    private var redoStack: [(raw: String, selection: NSRange)] = []
    private let undoLimit = 300

    var store: NoteStore?
    var onContentChange: ((Note) -> Void)?
    var onEscape: (() -> Void)?
    var onFocusLost: (() -> Void)?
    var onOpenNoteURL: ((URL) -> Void)?

    /// Lazily built: most sessions never type `:`, and a second window is not free.
    private var emojiPicker: EmojiPickerPanel?

    /// The trigger the user closed with Escape. Dismissing a window hands focus back, and AppKit
    /// answers that with a selection notification — without remembering the dismissal, Escape would
    /// close the grid and it would be back a run-loop tick later. Cleared as soon as the trigger
    /// changes or the caret leaves its line, so nothing is permanently switched off.
    private var dismissedTrigger: String?

    // MARK: setup

    init() {
        editor = MarkdownEditor.make()
        decorationLayout = editor.layoutManager as! DecorationLayoutManager
        render = NoteRenderer.render("", theme: Prefs.theme)
        super.init(frame: .zero)

        editor.host = self
        editor.delegate = self
        editor.onEscape = { [weak self] in self?.onEscape?() }
        editor.onEmojiKey = { [weak self] event in self?.handleEmojiKey(event) ?? false }

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
        pendingEdit = nil
        self.note = note
        undoStack.removeAll()
        redoStack.removeAll()
        emojiPicker?.dismiss()
        let caret = caretAtEnd ? (note.body as NSString).length : 0
        render = Self.render(note.body, caretRaw: caret)
        applyRender(caretRaw: caret, length: 0)
    }

    /// Re-render in place, e.g. after the font size or appearance changed.
    func refreshTheme() {
        guard let note else { return }
        let caret = selectedRawRange.location
        let length = selectedRawRange.length
        render = Self.render(note.body, caretRaw: caret)
        applyRender(caretRaw: caret, length: length)
    }

    func clear() {
        note = nil
        render = NoteRenderer.render("", theme: Prefs.theme)
        applyRender(caretRaw: 0, length: 0)
    }

    // MARK: display ⇄ raw

    /// Reveal inline source while editing; completed block prefixes stay rendered.
    private static func render(_ raw: String, caretRaw: Int) -> NoteRender {
        NoteRenderer.render(raw, theme: Prefs.theme, revealing: caretRaw)
    }

    private func applyRender(caretRaw: Int, length: Int) {
        isApplying = true
        defer { isApplying = false }
        let display = render.display
        if let storage = editor.textStorage {
            // Keep unchanged glyphs and layout intact. Replacing the whole storage on every
            // keystroke invalidates every paragraph and makes scrolling and the caret jump.
            let change = Self.diff(old: storage.string, new: display.string)
            storage.beginEditing()
            if change.length > 0 || !change.inserted.isEmpty {
                storage.replaceCharacters(in: NSRange(location: change.location, length: change.length), with: change.inserted)
            }
            display.enumerateAttributes(in: NSRange(location: 0, length: display.length)) { attributes, range, _ in
                var offset = range.location
                while offset < NSMaxRange(range) {
                    var effective = NSRange()
                    let existing = storage.attributes(at: offset, effectiveRange: &effective)
                    let span = NSRange(location: offset, length: min(NSMaxRange(effective), NSMaxRange(range)) - offset)
                    var desired = attributes
                    // The renderer creates attachment objects, but unchanged checkboxes share
                    // their cached image. Keep the existing object to avoid invalidating every task.
                    if let old = existing[.attachment] as? NSTextAttachment,
                       let new = attributes[.attachment] as? NSTextAttachment,
                       old.image === new.image, old.bounds == new.bounds {
                        desired[.attachment] = old
                    }
                    if !(existing as NSDictionary).isEqual(to: desired) {
                        storage.setAttributes(desired, range: span)
                    }
                    offset = NSMaxRange(span)
                }
            }
            storage.endEditing()
        }
        decorationLayout.update(render: render, theme: Prefs.theme)
        let start = render.displayOffsetForCaret(caretRaw)
        let end = render.displayOffsetForCaret(caretRaw + length)
        editor.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        editor.scrollRangeToVisible(editor.selectedRange())
        var attributes: [NSAttributedString.Key: Any] = [.font: Prefs.theme.baseFont, .foregroundColor: NSColor.labelColor]
        if let block = render.blocks.first(where: { $0.rawRange.lowerBound <= caretRaw && caretRaw <= $0.rawRange.upperBound }),
           case .heading(let level) = block.kind {
            attributes[.font] = Prefs.theme.headingFont(level: level)
        }
        editor.typingAttributes = attributes
        lastDisplay = display.string
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard !isApplying, let replacementString else { return true }
        // AppKit supplies the exact edit. A string diff alone cannot locate an insertion in
        // repeated text and can split the surrogate pair of an emoji.
        if !textView.hasMarkedText(), textView.string == lastDisplay {
            pendingEdit = (affectedCharRange, replacementString, selectedRawRange)
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplying, note != nil else { return }
        // While an IME is composing, the marked text is not committed markdown yet. The whole
        // composition arrives as one change once it commits, because we keep `lastDisplay` at
        // its pre-composition value.
        if editor.hasMarkedText() { return }
        commitDisplayChange()
    }

    /// Moving the caret can open or close the picker: leaving the `:` line must dismiss it, and
    /// clicking back onto one must bring it up again.
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplying else { return }
        // A mouse drag is still choosing the selection; swapping the text under it would break
        // the drag. `MarkdownEditor.mouseDown` calls back once the button is up.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        revealCaretBlock()
        refreshEmojiPicker()
    }

    /// Re-renders when the caret changes blocks, revealing inline source in the active block.
    func revealCaretBlock() {
        guard let note, !isApplying, !editor.hasMarkedText(),
              // Typed text not committed yet: the old render cannot map the new display.
              editor.string == lastDisplay else { return }
        let selection = selectedRawRange
        guard render.revealableRawRange(forCaret: selection.location) != render.revealedRawRange else { return }
        render = Self.render(note.body, caretRaw: selection.location)
        applyRender(caretRaw: selection.location, length: selection.length)
        // Inside a selection change the text view only redraws the caret's line; the block that
        // just hid its markers would keep showing them.
        editor.needsDisplay = true
    }

    private func commitDisplayChange() {
        guard let note else { return }
        let newDisplay = editor.string
        guard newDisplay != lastDisplay else { return }
        let edit = pendingEdit
        pendingEdit = nil
        let exact = edit.flatMap { edit -> (location: Int, length: Int, inserted: String)? in
            guard NSMaxRange(edit.range) <= lastDisplay.utf16.count,
                  (lastDisplay as NSString).replacingCharacters(in: edit.range, with: edit.text) == newDisplay else { return nil }
            return (edit.range.location, edit.range.length, edit.text)
        }
        let (loc, len, inserted) = exact ?? Self.diff(old: lastDisplay, new: newDisplay)

        let previousRaw = note.body
        let rawRange = rawRangeForEdit(NSRange(location: loc, length: len))
        var newRaw = (previousRaw as NSString).replacingCharacters(in: rawRange, with: inserted)
        guard newRaw != previousRaw else { return }

        pushUndo(raw: previousRaw, selection: edit?.selection ?? rawRange)
        var caretRaw = rawRange.location + (inserted as NSString).length
        if inserted == "]", let completed = EditorCommands.InputRule.completeTask(raw: newRaw, caret: caretRaw) {
            newRaw = completed.raw
            caretRaw = completed.caret
        }
        note.body = newRaw
        store?.scheduleSave(note)
        render = Self.render(newRaw, caretRaw: caretRaw)
        applyRender(caretRaw: caretRaw, length: 0)
        onContentChange?(note)
        refreshEmojiPicker()
    }

    /// One replaced range between two strings: the shared prefix and suffix are trimmed away.
    static func diff(old: String, new: String) -> (location: Int, length: Int, inserted: String) {
        let o = old as NSString
        let n = new as NSString
        let limit = min(o.length, n.length)
        var prefix = 0
        while prefix < limit, o.character(at: prefix) == n.character(at: prefix) { prefix += 1 }
        if prefix > 0, prefix < o.length {
            prefix = min(prefix, o.rangeOfComposedCharacterSequence(at: prefix).location)
        }
        if prefix > 0, prefix < n.length {
            prefix = min(prefix, n.rangeOfComposedCharacterSequence(at: prefix).location)
        }
        var suffix = 0
        while suffix < (limit - prefix),
              o.character(at: o.length - 1 - suffix) == n.character(at: n.length - 1 - suffix) { suffix += 1 }
        // Do not retain half a composed character as the common suffix.
        if suffix > 0 {
            let oldStart = o.length - suffix
            let newStart = n.length - suffix
            let oldBoundary = o.rangeOfComposedCharacterSequence(at: oldStart)
            let newBoundary = n.rangeOfComposedCharacterSequence(at: newStart)
            if oldBoundary.location < oldStart { suffix -= NSMaxRange(oldBoundary) - oldStart }
            if newBoundary.location < newStart { suffix = min(suffix, n.length - NSMaxRange(newBoundary)) }
        }
        let removed = NSRange(location: prefix, length: o.length - prefix - suffix)
        let inserted = n.substring(with: NSRange(location: prefix, length: n.length - prefix - suffix))
        return (removed.location, removed.length, inserted)
    }

    // MARK: selections

    /// The current display selection mapped into raw markdown offsets.
    var selectedRawRange: NSRange {
        rawRangeForEdit(editor.selectedRange())
    }

    private func rawRangeForEdit(_ range: NSRange) -> NSRange {
        if range.location == 0, range.length > 0, range.length == render.displayLength {
            return NSRange(location: 0, length: render.rawLength)
        }
        return render.rawRange(forDisplayRange: range)
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
        render = Self.render(raw, caretRaw: selection.location)
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
        render = Self.render(newRaw, caretRaw: caretRaw)
        applyRender(caretRaw: caretRaw, length: length)
        onContentChange?(note)
        refreshEmojiPicker()
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
        guard let note, editor.selectedRange().length == 0 else { return false }
        let caret = selectedRawRange.location
        guard let result = EditorCommands.InputRule.continuation(raw: note.body, caret: caret) else { return false }
        applyReplace(result.raw, caretRaw: result.caret)
        return true
    }

    /// Backspace at the beginning of rendered content removes its block prefix first.
    func handleBackspace() -> Bool {
        guard let note, editor.selectedRange().length == 0 else { return false }
        let caret = selectedRawRange.location
        guard let block = MarkdownParser.parse(note.body).first(where: {
            $0.contentRange.lowerBound == caret && $0.rawRange.lowerBound < caret
        }) else { return false }
        switch block.kind {
        case .heading, .listItem, .blockquote:
            let range = NSRange(location: block.rawRange.lowerBound, length: caret - block.rawRange.lowerBound)
            applyReplace((note.body as NSString).replacingCharacters(in: range, with: ""), caretRaw: range.location)
            return true
        default: return false
        }
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
        render = Self.render(newRaw, caretRaw: caret)
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

    /// Closes the picker if it is open. Called when the panel goes away.
    func dismissEmojiPicker() {
        emojiPicker?.dismiss()
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

    // MARK: emoji picker

    /// The picker is open for a trailing `:` at the end of a line. The query is whatever follows
    /// that colon, taken straight from the raw markdown — see `EmojiTrigger`.
    private var emojiQuery: String? {
        guard let note else { return nil }
        return EmojiTrigger.query(in: note.body, caret: selectionAnchorRaw())
    }

    /// Shows, updates or hides the picker so it always matches the caret's line.
    private func refreshEmojiPicker() {
        guard let query = emojiQuery, let window else {
            emojiPicker?.dismiss()
            // Off the trigger line: the next colon starts fresh.
            dismissedTrigger = nil
            return
        }
        let trigger = ":" + query
        guard dismissedTrigger != trigger else {
            emojiPicker?.dismiss()
            return
        }
        dismissedTrigger = nil
        let panel = ensureEmojiPicker()
        panel.picker.show(query: query)
        panel.present(anchor: caretScreenRect(), in: window)
    }

    private func ensureEmojiPicker() -> EmojiPickerPanel {
        if let emojiPicker { return emojiPicker }
        let panel = EmojiPickerPanel()
        panel.picker.onPick = { [weak self] emoji in
            self?.emojiPicker?.dismiss()
            self?.insertEmoji(emoji)
        }
        emojiPicker = panel
        return panel
    }

    /// Keys the picker owns while it is open: the arrows walk the grid, Return and Tab take the
    /// highlighted emoji, Escape closes the grid and leaves the panel (and the colon) alone.
    /// Left and right are deliberately *not* swallowed — moving the caret out of the trigger line
    /// is a legitimate way to abandon the picker.
    private func handleEmojiKey(_ event: NSEvent) -> Bool {
        guard let panel = emojiPicker, panel.isVisible else { return false }
        switch event.keyCode {
        case 53: // Escape
            dismissedTrigger = emojiQuery.map { ":" + $0 }
            panel.dismiss()
            return true
        case 126: // Arrow up
            panel.picker.moveSelection(dx: 0, dy: -1)
            return true
        case 125: // Arrow down
            panel.picker.moveSelection(dx: 0, dy: 1)
            return true
        case 36, 76, 48: // Return, keypad Enter, Tab
            panel.picker.pickCurrent()
            return true
        default:
            return false
        }
    }

    /// Replaces the colon and the query typed after it with the chosen emoji.
    func insertEmoji(_ emoji: String) {
        guard let note,
              let result = EmojiTrigger.insert(emoji, in: note.body, caret: selectionAnchorRaw()) else { return }
        applyReplace(result.raw, caretRaw: result.caret)
    }

    /// Where the caret is on screen, which is where the picker hangs from.
    private func caretScreenRect() -> NSRect {
        let display = editor.selectedRange().location
        let rect = editor.firstRect(forCharacterRange: NSRange(location: display, length: 0), actualRange: nil)
        guard rect.height > 0 else {
            // Should not happen for a laid-out text view, but a zero rect would drop the picker in
            // the screen corner, so fall back to the panel itself.
            return window?.frame ?? .zero
        }
        return rect
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
