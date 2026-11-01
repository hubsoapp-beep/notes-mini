import AppKit
import NotesMiniCore

/// `NSTextView` tuned for markdown: no smart substitutions (they corrupt the source), plain-text
/// paste, Escape to hide the panel, Tab to indent list items, Return to continue lists, and
/// click-to-toggle task checkboxes.
final class MarkdownEditor: NSTextView {

    weak var host: NoteEditorView?

    /// Escape hides the panel — the same gesture that closes Raycast's window.
    var onEscape: (() -> Void)?

    /// Keys the emoji picker owns while it is open. Asked before anything else, so the arrows move
    /// the grid and Return picks from it instead of editing the note. Returns true when consumed.
    var onEmojiKey: ((NSEvent) -> Bool)?

    static func make() -> MarkdownEditor {
        let storage = NSTextStorage()
        let layout = DecorationLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let editor = MarkdownEditor(frame: .zero, textContainer: container)
        editor.isRichText = true
        editor.drawsBackground = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = false // snapshot undo lives in NoteEditorView, over the raw markdown
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [NSView.AutoresizingMask.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 20, height: 16)
        editor.textContainer?.lineFragmentPadding = 0

        // Markdown source must survive the keyboard: no curly quotes, no em-dashes, no autocorrect.
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.usesFindPanel = true
        editor.usesRuler = false
        editor.importsGraphics = false

        editor.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL, NSPasteboard.PasteboardType.string])
        return editor
    }

    // MARK: input

    override func keyDown(with event: NSEvent) {
        // IME composition owns the keyboard until it commits.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        if onEmojiKey?(event) == true { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Escape
            if selectedRange().length > 0 {
                super.keyDown(with: event)
                return
            }
            onEscape?()
            return
        case 48: // Tab
            if flags.contains(.shift) {
                host?.indentSelection(increase: false)
            } else {
                host?.indentSelection(increase: true)
            }
            return
        case 36, 76: // Return / keypad Enter
            if !flags.contains(.shift), host?.handleReturn() == true { return }
        default:
            break
        }
        super.keyDown(with: event)
    }

    // MARK: drag & drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) { return .copy }
        if sender.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) { return .copy }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for url in urls {
                if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
                    host?.onOpenNoteURL?(url)
                    return true
                }
            }
            // Insert links for other files.
            let links = urls.map { "[\($0.lastPathComponent)](\($0.absoluteString))" }.joined(separator: " ")
            insertText(links, replacementRange: selectedRange())
            return true
        }
        if let str = sender.draggingPasteboard.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
            return true
        }
        return false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return host?.handleKeyEquivalent(event) ?? false
    }

    /// Paste always lands as plain markdown, never as styled RTF/HTML.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let note = host?.note {
            let dir = note.url.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "img-\(Int(Date().timeIntervalSince1970)).png"
            let url = dir.appendingPathComponent(name)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                insertText("![](attachments/\(name))", replacementRange: selectedRange())
                return
            }
        }
        let text = pb.string(forType: .string) ?? ""
        guard !text.isEmpty else { return }
        insertText(text, replacementRange: selectedRange())
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), host?.handleBackspace() == true { return }
        super.deleteBackward(sender)
    }

    // MARK: checkbox clicks

    override func mouseDown(with event: NSEvent) {
        if let host,
           let layout = layoutManager,
           let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let index = layout.characterIndex(for: inContainer,
                                              in: container,
                                              fractionOfDistanceBetweenInsertionPoints: nil)
            let length = (string as NSString).length
            for candidate in [index, index - 1] where candidate >= 0 && candidate < length {
                let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: candidate, length: 1), actualCharacterRange: nil)
                if layout.boundingRect(forGlyphRange: glyphs, in: container).contains(inContainer),
                   attributedString().attribute(.attachment, at: candidate, effectiveRange: nil) != nil,
                   host.toggleCheckbox(atDisplayOffset: candidate) {
                    return
                }
            }
        }
        super.mouseDown(with: event)
        // `super` tracks the drag until the button is released; only now is the caret settled.
        host?.revealCaretBlock()
    }

    /// The caret has no business inside an attachment; nudge it to the nearest text position.
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var range = charRange
        let length = (string as NSString).length
        if range.length == 0, length > 0, range.location < length,
           attributedString().attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
            range = NSRange(location: min(length, range.location + 1), length: 0)
        }
        super.setSelectedRange(range, affinity: affinity, stillSelecting: stillSelecting)
    }
}
