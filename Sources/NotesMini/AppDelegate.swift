import AppKit
import NotesMiniCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var store: NoteStore!
    private var panel: NotesPanelController!
    private var statusItem: NSStatusItem?
    private var prefsWindow: PreferencesWindowController?
    private var hotkeyFailed = false

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        let folder = Prefs.notesFolder ?? Prefs.defaultFolder
        if Prefs.notesFolder == nil { Prefs.notesFolder = folder }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        store = NoteStore(folder: folder)
        store.reload()
        store.startWatching()
        store.onChange = { [weak self] in
            // The save queue fires this from a background thread; UI work here would crash
            // on the main-queue assertion. On main it stays synchronous so a change made
            // during termination is not lost to an async hop that never runs.
            if Thread.isMainThread { self?.storeDidChange() }
            else { DispatchQueue.main.async { self?.storeDidChange() } }
        }

        panel = NotesPanelController(store: store)
        panel.onRequestNewNote = { [weak self] in self?.newNote(nil) }
        panel.onRequestBrowse = { [weak self] in self?.browseNotes(nil) }
        panel.onRequestActionPanel = { [weak self] in self?.showActionPanel(nil) }
        panel.onRequestPreferences = { [weak self] in self?.showPreferences(nil) }

        setUpStatusItem()
        registerHotkey()
        // The login item is derived state: never trust a plist left over from another copy.
        LaunchAtLogin.sync()

        // Open with the last note the user had; if that file is gone, fall back to the most
        // recently updated note rather than silently creating an empty one next to it.
        let lastURL = Prefs.lastNotePath.map { URL(fileURLWithPath: $0) }
        let restored: Note? = {
            if let lastURL, FileManager.default.fileExists(atPath: lastURL.path) {
                if let note = store.note(withURL: lastURL) ?? store.loadNote(at: lastURL) { return note }
            }
            return store.notes.first
        }()
        if let restored {
            panel.show(restored)
        } else {
            newNote(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.saveFrameNow()
        store?.flushAll()
        HotkeyCenter.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder and Spotlight send a reopen event when this accessory app is already running.
        // Restore the notes panel even if another window (such as Preferences) is visible.
        guard panel != nil else { return true }
        showPanel(nil)
        return false
    }

    // MARK: store helpers

    private var currentNote: Note? { panel?.currentNote }

    private func ensureNote() -> Note {
        if let note = currentNote { return note }
        return store.notes.first ?? store.createNote()
    }

    // MARK: actions

    @objc func newNote(_ sender: Any?) {
        let note = store.createNote()
        panel.show(note)
        panel.dismissOverlay()
        panel.refreshCurrentNote()
        refreshStatusMenu()
    }

    @objc func showPanel(_ sender: Any?) {
        panel.show(ensureNote())
    }

    @objc func hidePanel(_ sender: Any?) {
        panel.hide()
    }

    @objc func togglePanel(_ sender: Any?) {
        if panel.panel.isVisible && panel.panel.isKeyWindow {
            panel.hide()
        } else {
            panel.show(ensureNote())
        }
    }

    @objc func browseNotes(_ sender: Any?) {
        let notes = store.notes
        let items = notes.map { note in
            OverlayItem(
                title: note.uiTitle,
                subtitle: note.preview(maxLength: 90),
                symbol: note.isPinned ? "pin.fill" : "doc.text",
                accessory: Self.relativeDate(note.updated)
            ) { [weak self] in
                guard let self else { return }
                self.panel.dismissOverlay()
                self.panel.show(note)
                self.refreshStatusMenu()
            }
        }
        panel.presentOverlay(items: items,
                             placeholder: "Szukaj notatek…",
                             emptyText: notes.isEmpty ? "Brak notatek" : "Nic nie znaleziono")
    }

    @objc func showActionPanel(_ sender: Any?) {
        let note = currentNote
        var items: [OverlayItem] = []
        items.append(OverlayItem(title: "Nowa notatka", symbol: "square.and.pencil", accessory: "⌘N") { [weak self] in
            self?.panel.dismissOverlay()
            self?.newNote(nil)
        })
        items.append(OverlayItem(title: "Przeglądaj notatki", symbol: "list.bullet.rectangle", accessory: "⌘P") { [weak self] in
            self?.browseNotes(nil)
        })
        if let note {
            items.append(OverlayItem(title: note.isPinned ? "Odepnij notatkę" : "Przypnij notatkę",
                                     symbol: note.isPinned ? "pin.slash" : "pin",
                                     accessory: "⇧⌘P") { [weak self] in
                guard let self else { return }
                self.panel.dismissOverlay()
                self.store.togglePinned(note)
                self.panel.refreshCurrentNote()
                self.refreshStatusMenu()
            })
            items.append(OverlayItem(title: "Zapisz jako Markdown…", symbol: "arrow.down.doc", accessory: "⇧⌘S") { [weak self] in
                self?.panel.dismissOverlay()
                self?.exportMarkdown(nil)
            })
            items.append(OverlayItem(title: "Kopiuj jako Markdown", symbol: "doc.on.doc", accessory: "⌥⌘C") { [weak self] in
                guard let self else { return }
                self.panel.dismissOverlay()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.body, forType: .string)
            })
            items.append(OverlayItem(title: "Pokaż w Finderze", symbol: "folder") { [weak self] in
                self?.panel.dismissOverlay()
                NSWorkspace.shared.activateFileViewerSelecting([note.url])
            })
            items.append(OverlayItem(title: "Przenieś do kosza", symbol: "trash") { [weak self] in
                guard let self else { return }
                self.panel.dismissOverlay()
                self.trashNote(nil)
            })
            if !store.trashedNotes().isEmpty {
                items.append(OverlayItem(title: "Przywróć z kosza", symbol: "arrow.uturn.backward") { [weak self] in
                    guard let self else { return }
                    self.panel.dismissOverlay()
                    self.showTrashRestore()
                })
            }
        }
        items.append(OverlayItem(title: "Ustawienia…", symbol: "gearshape", accessory: "⌘,") { [weak self] in
            self?.panel.dismissOverlay()
            self?.showPreferences(nil)
        })

        panel.presentOverlay(items: items,
                             placeholder: "Wpisz akcję…",
                             emptyText: "Brak pasujących akcji")
    }

    /// Full screen from the menu as well as the green button; hiding the traffic lights leaves the
    /// keyboard as the way back, so the shortcut has to exist.
    @objc func togglePanelFullScreen(_ sender: Any?) {
        panel?.zoomTapped()
    }

    @objc func togglePin(_ sender: Any?) {
        guard let note = currentNote else { return }
        store.togglePinned(note)
        panel.refreshCurrentNote()
        refreshStatusMenu()
    }

    @objc func trashNote(_ sender: Any?) {
        guard let note = currentNote else { return }
        store.trash(note)
        if let next = store.notes.first {
            panel.show(next)
        } else {
            panel.show(store.createNote())
        }
        refreshStatusMenu()
    }

    private func showTrashRestore() {
        let items = store.trashedNotes().map { url in
            OverlayItem(title: url.lastPathComponent, symbol: "doc.text") { [weak self] in
                guard let self else { return }
                if let note = self.store.restore(fromTrash: url) {
                    self.panel.dismissOverlay()
                    self.panel.show(note)
                    self.refreshStatusMenu()
                }
            }
        }
        panel.presentOverlay(items: items, placeholder: "Szukaj w koszu…", emptyText: "Kosz pusty")
    }

    @objc func exportMarkdown(_ sender: Any?) { export(as: .markdown) }
    @objc func exportPlainText(_ sender: Any?) { export(as: .plainText) }
    @objc func exportHTML(_ sender: Any?) { export(as: .html) }

    private func export(as format: ExportFormat) {
        guard let note = currentNote else { return }
        let window = panel.panel
        let save = NSSavePanel()
        save.nameFieldStringValue = Exporter.suggestedFilename(note, format: format)
        save.allowedContentTypes = format == .html ? [.html] : (format == .plainText ? [.plainText] : [.init(filenameExtension: "md")!])
        save.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = save.url else { return }
            try? Exporter.export(note, as: format).write(to: url, atomically: true, encoding: .utf8)
            self?.panel.show(note)
        }
    }

    @objc func revealNotesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(store.folder)
    }

    @objc func zoomIn(_ sender: Any?) { setFontSize(Prefs.fontSize + 1) }
    @objc func zoomOut(_ sender: Any?) { setFontSize(Prefs.fontSize - 1) }
    @objc func zoomReset(_ sender: Any?) { setFontSize(14) }

    private func setFontSize(_ size: CGFloat) {
        Prefs.fontSize = min(28, max(10, size))
        panel.editorView.refreshTheme()
        panel.refreshCurrentNote()
    }

    @objc func showPreferences(_ sender: Any?) {
        if prefsWindow == nil {
            prefsWindow = PreferencesWindowController(onChange: { [weak self] in
                guard let self else { return }
                self.store.changeFolder(Prefs.notesFolder ?? self.store.folder)
                self.registerHotkey()
                self.panel.panel.appearance = Prefs.nsAppearance
                self.panel.editorView.refreshTheme()
                self.refreshStatusMenu()
            })
        }
        activateNotesMini()
        prefsWindow?.showWindow(nil)
        prefsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // SF Symbol with an emoji fallback, so the item is never an invisible blank.
        if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Notes Mini") {
            item.button?.image = image
            item.button?.image?.isTemplate = true
        } else {
            item.button?.title = "📝"
        }
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshStatusMenu()
    }

    /// A save can rename the note's file, so the remembered path is refreshed here rather than only
    /// when the panel is shown: quitting right after a retitle would otherwise point the next
    /// launch at a file that no longer exists.
    private func storeDidChange() {
        refreshStatusMenu()
        if let note = currentNote {
            if Prefs.lastNotePath != note.url.path { Prefs.lastNotePath = note.url.path }
            // External edits (e.g. Obsidian) overwrite only when the local buffer is clean.
            if !store.isPending(note),
               let fresh = store.note(withURL: note.url) ?? store.loadNote(at: note.url),
               fresh.body != panel.currentNote?.body {
                // Compare against what the editor actually shows.
                if fresh.body != editorText() {
                    panel.show(fresh)
                }
            }
        }
    }

    private func editorText() -> String {
        panel.currentEditorText()
    }

    private func refreshStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let showTitle = hotkeyFailed ? "Pokaż notatnik (skrót zajęty)" : "Pokaż notatnik (\(HotkeyCenter.display(Prefs.hotkey)))"
        let show = NSMenuItem(title: showTitle, action: #selector(showPanel(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let new = NSMenuItem(title: "Nowa notatka", action: #selector(newNote(_:)), keyEquivalent: "")
        new.target = self
        menu.addItem(new)
        menu.addItem(.separator())

        // Five most recent notes for quick access.
        for note in store.notes.prefix(5) {
            let title = note.uiTitle
            let entry = NSMenuItem(title: title, action: #selector(openNoteFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = note.url
            entry.state = (note.url == currentNote?.url) ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let browse = NSMenuItem(title: "Przeglądaj notatki…", action: #selector(browseNotes(_:)), keyEquivalent: "")
        browse.target = self
        menu.addItem(browse)

        let reveal = NSMenuItem(title: "Pokaż folder notatek", action: #selector(revealNotesFolder(_:)), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let prefs = NSMenuItem(title: "Ustawienia…", action: #selector(showPreferences(_:)), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Zakończ Notes Mini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openNoteFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let note = store.note(withURL: url) ?? store.loadNote(at: url) else { return }
        panel.show(note)
        refreshStatusMenu()
    }

    @objc private func statusItemClicked() {
        statusItem?.button?.performClick(nil)
    }

    // MARK: hotkey

    private func registerHotkey() {
        let spec = Prefs.hotkey
        let ok = HotkeyCenter.shared.register(spec) { [weak self] in
            self?.togglePanel(nil)
        }
        hotkeyFailed = !ok
        if !ok {
            NSLog("[NotesMini] nie udało się zarejestrować skrótu \(spec)")
            refreshStatusMenu()
        }
    }

    private static func relativeDate(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "teraz" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) godz." }
        let days = Int(seconds / 86400)
        if days < 7 { return "\(days) dn." }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "pl_PL")
        return f.string(from: date)
    }

    // MARK: menu

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "O Notes Mini", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Ustawienia…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Ukryj notatnik", action: #selector(hidePanel(_:)), keyEquivalent: "w")
        hide.target = self
        appMenu.addItem(hide)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Zakończ Notes Mini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Notatka")
        fileMenu.addItem(menuItem("Nowa notatka", #selector(newNote(_:)), "n", target: self))
        fileMenu.addItem(menuItem("Przeglądaj notatki…", #selector(browseNotes(_:)), "p", target: self))
        fileMenu.addItem(menuItem("Akcje…", #selector(showActionPanel(_:)), "k", target: self))
        fileMenu.addItem(menuItem("Przypnij / odepnij", #selector(togglePin(_:)), "P", target: self))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Zapisz jako Markdown…", #selector(exportMarkdown(_:)), "S", target: self))
        fileMenu.addItem(menuItem("Przenieś do kosza", #selector(trashNote(_:)), "\u{8}", target: self))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edycja")
        editMenu.addItem(NSMenuItem(title: "Cofnij", action: #selector(NoteEditorView.undoAction(_:)), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Ponów", action: #selector(NoteEditorView.redoAction(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Kopiuj jako Markdown", action: #selector(NoteEditorView.copyAsMarkdownAction(_:)), keyEquivalent: "c", modifiers: [.command, .option]))
        editMenu.addItem(NSMenuItem(title: "Kopiuj jako tekst", action: #selector(NoteEditorView.copyAsPlainTextAction(_:)), keyEquivalent: "c", modifiers: [.command, .option, .shift]))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let formatItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(NSMenuItem(title: "Pogrubienie", action: #selector(NoteEditorView.toggleBoldAction(_:)), keyEquivalent: "b"))
        formatMenu.addItem(NSMenuItem(title: "Kursywa", action: #selector(NoteEditorView.toggleItalicAction(_:)), keyEquivalent: "i"))
        formatMenu.addItem(NSMenuItem(title: "Podkreślenie", action: #selector(NoteEditorView.toggleUnderlineAction(_:)), keyEquivalent: "u"))
        formatMenu.addItem(NSMenuItem(title: "Przekreślenie", action: #selector(NoteEditorView.toggleStrikeAction(_:)), keyEquivalent: "x", modifiers: [.command, .shift]))
        formatMenu.addItem(NSMenuItem(title: "Kod inline", action: #selector(NoteEditorView.toggleCodeAction(_:)), keyEquivalent: "e"))
        formatMenu.addItem(NSMenuItem(title: "Link…", action: #selector(NoteEditorView.insertLinkAction(_:)), keyEquivalent: "l"))
        formatMenu.addItem(.separator())
        formatMenu.addItem(NSMenuItem(title: "Nagłówek 1", action: #selector(NoteEditorView.heading1Action(_:)), keyEquivalent: "1", modifiers: [.command, .option]))
        formatMenu.addItem(NSMenuItem(title: "Nagłówek 2", action: #selector(NoteEditorView.heading2Action(_:)), keyEquivalent: "2", modifiers: [.command, .option]))
        formatMenu.addItem(NSMenuItem(title: "Nagłówek 3", action: #selector(NoteEditorView.heading3Action(_:)), keyEquivalent: "3", modifiers: [.command, .option]))
        formatMenu.addItem(.separator())
        formatMenu.addItem(NSMenuItem(title: "Lista punktowana", action: #selector(NoteEditorView.bulletListAction(_:)), keyEquivalent: "8", modifiers: [.command, .shift]))
        formatMenu.addItem(NSMenuItem(title: "Lista numerowana", action: #selector(NoteEditorView.orderedListAction(_:)), keyEquivalent: "9", modifiers: [.command, .option]))
        formatMenu.addItem(NSMenuItem(title: "Lista zadań", action: #selector(NoteEditorView.taskListAction(_:)), keyEquivalent: "7", modifiers: [.command, .shift]))
        formatMenu.addItem(NSMenuItem(title: "Cytat", action: #selector(NoteEditorView.quoteAction(_:)), keyEquivalent: "'", modifiers: [.command, .shift]))
        formatMenu.addItem(NSMenuItem(title: "Blok kodu", action: #selector(NoteEditorView.codeBlockAction(_:)), keyEquivalent: "9", modifiers: [.command, .shift]))
        formatMenu.addItem(NSMenuItem(title: "Linia pozioma", action: #selector(NoteEditorView.horizontalRuleAction(_:)), keyEquivalent: "-", modifiers: [.command, .shift]))
        formatMenu.addItem(.separator())
        formatMenu.addItem(NSMenuItem(title: "Wyczyść formatowanie", action: #selector(NoteEditorView.clearFormatAction(_:)), keyEquivalent: "0", modifiers: [.command, .shift]))
        formatItem.submenu = formatMenu
        main.addItem(formatItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Widok")
        viewMenu.addItem(menuItem("Większa czcionka", #selector(zoomIn(_:)), "+", target: self))
        viewMenu.addItem(menuItem("Mniejsza czcionka", #selector(zoomOut(_:)), "-", target: self))
        viewMenu.addItem(menuItem("Domyślny rozmiar", #selector(zoomReset(_:)), "0", target: self))
        viewMenu.addItem(.separator())
        let fullScreen = NSMenuItem(title: "Pełny ekran", action: #selector(togglePanelFullScreen(_:)),
                                    keyEquivalent: "f", modifiers: [.command, .control])
        fullScreen.target = self
        viewMenu.addItem(fullScreen)
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String = "",
                          _ modifiers: NSEvent.ModifierFlags = [.command],
                          target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, modifiers: NSEvent.ModifierFlags, target: AnyObject? = nil) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.keyEquivalentModifierMask = modifiers
        self.target = target
    }
}
