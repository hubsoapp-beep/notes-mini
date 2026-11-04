import AppKit
import NotesMiniCore

/// Small settings window. Everything applies immediately — there is no OK/Cancel pair, because
/// every option is visible in the panel behind it.
final class PreferencesWindowController: NSWindowController {

    private let onChange: () -> Void

    private let folderLabel = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider(value: 14, minValue: 10, maxValue: 28, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "14 pt")
    private let appearancePopup = NSPopUpButton()
    private let hotkeyField = NSTextField()
    private let hotkeyHint = NSTextField(labelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "Uruchamiaj przy logowaniu", target: nil, action: nil)

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Notes Mini — ustawienia"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        reload()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: UI

    private func build() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Notes Mini")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let folderTitle = NSTextField(labelWithString: "Folder notatek")
        folderTitle.font = .systemFont(ofSize: 11, weight: .medium)
        folderTitle.textColor = .secondaryLabelColor
        folderLabel.textColor = .labelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        let chooseButton = NSButton(title: "Zmień…", target: self, action: #selector(chooseFolder))
        let revealButton = NSButton(title: "Pokaż", target: self, action: #selector(revealFolder))

        let sizeTitle = NSTextField(labelWithString: "Rozmiar czcionki")
        sizeTitle.font = .systemFont(ofSize: 11, weight: .medium)
        sizeTitle.textColor = .secondaryLabelColor
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.numberOfTickMarks = 19
        sizeSlider.allowsTickMarkValuesOnly = true
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let appearanceTitle = NSTextField(labelWithString: "Wygląd")
        appearanceTitle.font = .systemFont(ofSize: 11, weight: .medium)
        appearanceTitle.textColor = .secondaryLabelColor
        appearancePopup.addItems(withTitles: ["Jak w systemie", "Jasny", "Ciemny"])
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)

        let hotkeyTitle = NSTextField(labelWithString: "Skrót globalny")
        hotkeyTitle.font = .systemFont(ofSize: 11, weight: .medium)
        hotkeyTitle.textColor = .secondaryLabelColor
        hotkeyField.placeholderString = Prefs.defaultHotkey
        hotkeyField.target = self
        hotkeyField.action = #selector(hotkeyChanged)
        hotkeyHint.textColor = .tertiaryLabelColor
        hotkeyHint.font = .systemFont(ofSize: 11)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)

        let grid = NSGridView(views: [
            [title, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, NSGridCell.emptyContentView],
            [folderTitle, folderLabel],
            [NSGridCell.emptyContentView, hstack([chooseButton, revealButton])],
            [sizeTitle, hstack([sizeSlider, sizeLabel])],
            [appearanceTitle, appearancePopup],
            [hotkeyTitle, hstack([hotkeyField, hotkeyHint])],
            [NSGridCell.emptyContentView, loginCheckbox],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            hotkeyField.widthAnchor.constraint(equalToConstant: 110),
            sizeSlider.widthAnchor.constraint(equalToConstant: 200),
            folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    // MARK: state

    private func reload() {
        folderLabel.stringValue = (Prefs.notesFolder ?? Prefs.defaultFolder).path
        sizeSlider.doubleValue = Double(Prefs.fontSize)
        sizeLabel.stringValue = "\(Int(Prefs.fontSize)) pt"
        appearancePopup.selectItem(at: ["system", "light", "dark"].firstIndex(of: Prefs.appearance) ?? 0)
        hotkeyField.stringValue = Prefs.hotkey
        hotkeyHint.stringValue = HotkeyCenter.display(Prefs.hotkey)
        loginCheckbox.state = Prefs.launchAtLogin ? .on : .off
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Prefs.notesFolder ?? Prefs.defaultFolder
        panel.prompt = "Wybierz"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.notesFolder = url
        reload()
        onChange()
    }

    @objc private func revealFolder() {
        NSWorkspace.shared.open(Prefs.notesFolder ?? Prefs.defaultFolder)
    }

    @objc private func sizeChanged() {
        Prefs.fontSize = CGFloat(sizeSlider.doubleValue)
        sizeLabel.stringValue = "\(Int(Prefs.fontSize)) pt"
        onChange()
    }

    @objc private func appearanceChanged() {
        Prefs.appearance = ["system", "light", "dark"][max(0, appearancePopup.indexOfSelectedItem)]
        onChange()
    }

    @objc private func hotkeyChanged() {
        let spec = hotkeyField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        if HotkeyCenter.parse(spec) == nil {
            hotkeyHint.stringValue = "nieznany skrót"
            hotkeyHint.textColor = .systemRed
            return
        }
        Prefs.hotkey = spec
        hotkeyField.stringValue = spec
        hotkeyHint.textColor = .tertiaryLabelColor
        hotkeyHint.stringValue = HotkeyCenter.display(spec)
        onChange()
    }

    @objc private func loginChanged() {
        Prefs.launchAtLogin = loginCheckbox.state == .on
        LaunchAtLogin.set(enabled: Prefs.launchAtLogin)
        onChange()
    }
}
