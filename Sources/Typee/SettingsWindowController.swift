import AppKit

final class SettingsPanel: NSPanel {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SettingsWindowController: NSWindowController {
    private weak var appDelegate: AppDelegate?
    private let hotkeyManager: HotkeyManager
    private let noteStore: NoteStore

    private var startupCheckbox:  NSButton!
    private var autoHideCheckbox: NSButton!
    private var hotkeyControl:    NSSegmentedControl!
    private var pathLabel:        NSTextField!
    private var checkUpdatesBtn:  NSButton!
    private var fontSlider:       NSSlider!
    private var opacSlider:       NSSlider!
    private var fontValueLabel:   NSTextField!
    private var opacValueLabel:   NSTextField!

    init(appDelegate: AppDelegate, hotkeyManager: HotkeyManager, noteStore: NoteStore) {
        self.appDelegate   = appDelegate
        self.hotkeyManager = hotkeyManager
        self.noteStore     = noteStore
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
            styleMask:   [.titled, .closable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        panel.title                       = "Typee Settings"
        panel.titlebarAppearsTransparent  = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate           = false
        panel.level                       = .floating
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if let w = window {
            if !w.isVisible { w.center() }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ── ABOUT HEADER ──────────────────────────────────────────

        let iconView = NSImageView()
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            iconView.image = appIcon
        } else {
            iconView.image = NSImage(systemSymbolName: "square.and.pencil",
                                     accessibilityDescription: nil)
            iconView.contentTintColor = .labelColor
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 20, y: 518, width: 40, height: 40)

        let appNameLabel = label("Typee", size: 20, weight: .bold)
        appNameLabel.frame = NSRect(x: 68, y: 538, width: 272, height: 24)

        let versionLabel = label("Version \(kAppVersion)", size: 12, color: .secondaryLabelColor)
        versionLabel.frame = NSRect(x: 68, y: 520, width: 272, height: 14)

        let madeLabel = label("Made with \u{2665} by Reyansh Nangia",
                               size: 11, color: .tertiaryLabelColor)
        madeLabel.alignment = .center
        madeLabel.frame = NSRect(x: 20, y: 502, width: 340, height: 14)

        let sep0 = divider(y: 492)

        // ── HOW TO USE ────────────────────────────────────────────

        let howLabel = sectionLabel("How to Use")
        howLabel.frame = NSRect(x: 20, y: 474, width: 340, height: 14)
        let sep_how = divider(y: 470)

        let tipStrings = [
            "Double-tap  ⌃ · ⌥ · ⌘  to show and hide Typee",
            "⌘N  new note  ·  ⌘⇧N  delete  ·  ⌘W / Esc  hide",
            "⌘[  /  ⌘]  navigate  ·  swipe left or right",
            "⌘B  bold  ·  ⌘U  underline  ·  ⌘=  /  ⌘−  text size",
        ]
        let tipYs: [CGFloat] = [446, 422, 398, 374]
        var tips: [NSTextField] = []
        for (str, y) in zip(tipStrings, tipYs) {
            let t = label(str, size: 12, color: .secondaryLabelColor)
            t.frame = NSRect(x: 26, y: y, width: 328, height: 18)
            tips.append(t)
        }

        // ── APPEARANCE ────────────────────────────────────────────

        let appearLabel = sectionLabel("Appearance")
        appearLabel.frame = NSRect(x: 20, y: 346, width: 340, height: 14)
        let sep_app = divider(y: 342)

        let savedOpacity = {
            let v = UserDefaults.standard.double(forKey: "typee.windowOpacity")
            return v > 0 ? v : 1.0
        }()
        let savedFontSize = {
            let v = UserDefaults.standard.double(forKey: "typee.fontSize")
            return v > 0 ? v : 15.0
        }()

        let opacLbl = label("Opacity", size: 13, color: .secondaryLabelColor)
        opacLbl.frame = NSRect(x: 24, y: 316, width: 96, height: 18)

        opacSlider = NSSlider(value: savedOpacity, minValue: 0.2, maxValue: 1.0,
                              target: self, action: #selector(opacSliderChanged))
        opacSlider.isContinuous = true
        opacSlider.frame = NSRect(x: 126, y: 312, width: 184, height: 26)

        opacValueLabel = label(opacPercent(savedOpacity), size: 12, color: .tertiaryLabelColor)
        opacValueLabel.frame = NSRect(x: 316, y: 316, width: 44, height: 18)

        let fontLbl = label("Font Size", size: 13, color: .secondaryLabelColor)
        fontLbl.frame = NSRect(x: 24, y: 276, width: 96, height: 18)

        fontSlider = NSSlider(value: savedFontSize, minValue: 10, maxValue: 28,
                              target: self, action: #selector(fontSliderChanged))
        fontSlider.isContinuous = true
        fontSlider.frame = NSRect(x: 126, y: 272, width: 184, height: 26)

        fontValueLabel = label("\(Int(savedFontSize)) pt", size: 12, color: .tertiaryLabelColor)
        fontValueLabel.frame = NSRect(x: 316, y: 276, width: 44, height: 18)

        // ── GENERAL ───────────────────────────────────────────────

        let genLabel = sectionLabel("General")
        genLabel.frame = NSRect(x: 20, y: 244, width: 340, height: 14)
        let sep1 = divider(y: 240)

        startupCheckbox = NSButton(checkboxWithTitle: "Launch at Startup",
                                   target: self, action: #selector(startupToggled))
        startupCheckbox.frame = NSRect(x: 24, y: 214, width: 312, height: 22)
        startupCheckbox.state = launchAtStartupEnabled ? .on : .off

        autoHideCheckbox = NSButton(checkboxWithTitle: "Hide when switching to another app",
                                    target: self, action: #selector(autoHideToggled))
        autoHideCheckbox.frame = NSRect(x: 24, y: 184, width: 312, height: 22)
        autoHideCheckbox.state = UserDefaults.standard.bool(
            forKey: "typee.autoHideOnDeactivate") ? .on : .off

        // ── HOTKEY ────────────────────────────────────────────────

        let hotkeyLabel = sectionLabel("Hotkey")
        hotkeyLabel.frame = NSRect(x: 20, y: 160, width: 340, height: 14)
        let sep2 = divider(y: 156)

        let triggerLabel = label("Show with:", size: 13, color: .secondaryLabelColor)
        triggerLabel.frame = NSRect(x: 24, y: 130, width: 90, height: 22)

        hotkeyControl = NSSegmentedControl(
            labels: HotkeyKey.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self, action: #selector(hotkeyChanged))
        hotkeyControl.frame = NSRect(x: 118, y: 126, width: 222, height: 26)
        hotkeyControl.selectedSegment =
            HotkeyKey.allCases.firstIndex(of: hotkeyManager.currentKey) ?? 0

        // ── NOTES STORAGE ─────────────────────────────────────────

        let storageLabel = sectionLabel("Notes Storage")
        storageLabel.frame = NSRect(x: 20, y: 98, width: 340, height: 14)
        let sep3 = divider(y: 94)

        pathLabel = label(shortPath(noteStore.folder), size: 12, color: .secondaryLabelColor)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.frame   = NSRect(x: 24, y: 68, width: 196, height: 20)
        pathLabel.toolTip = noteStore.folder.path

        let changeBtn = NSButton(title: "Change…", target: self,
                                 action: #selector(changeNotesFolder))
        changeBtn.bezelStyle = .rounded
        changeBtn.frame = NSRect(x: 236, y: 66, width: 118, height: 24)

        let revealBtn = NSButton(title: "Show in Finder", target: self,
                                 action: #selector(revealInFinder))
        revealBtn.bezelStyle = .inline
        revealBtn.isBordered = true
        revealBtn.font       = .systemFont(ofSize: 11)
        revealBtn.frame = NSRect(x: 24, y: 46, width: 116, height: 18)

        // ── FOOTER ────────────────────────────────────────────────

        let sep4 = divider(y: 38)

        checkUpdatesBtn = NSButton(title: "Check for Updates",
                                   target: self, action: #selector(checkForUpdates))
        checkUpdatesBtn.bezelStyle = .rounded
        checkUpdatesBtn.frame = NSRect(x: 16, y: 6, width: 152, height: 28)

        let done = NSButton(title: "Done", target: self, action: #selector(closeSelf))
        done.bezelStyle    = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 268, y: 6, width: 96, height: 28)

        var allViews: [NSView] = [
            iconView, appNameLabel, versionLabel, madeLabel, sep0,
            howLabel, sep_how,
            appearLabel, sep_app,
            opacLbl, opacSlider, opacValueLabel,
            fontLbl, fontSlider, fontValueLabel,
            genLabel, sep1, startupCheckbox, autoHideCheckbox,
            hotkeyLabel, sep2, triggerLabel, hotkeyControl,
            storageLabel, sep3, pathLabel, changeBtn, revealBtn,
            sep4, checkUpdatesBtn, done,
        ]
        allViews += tips
        allViews.forEach { cv.addSubview($0) }
    }

    // MARK: - Helpers

    private func label(_ text: String,
                        size: CGFloat,
                        weight: NSFont.Weight = .regular,
                        color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font      = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        return f
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text.uppercased())
        f.font      = .systemFont(ofSize: 10, weight: .semibold)
        f.textColor = .tertiaryLabelColor
        return f
    }

    private func divider(y: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 20, y: y, width: 340, height: 1))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func updatePathDisplay() {
        pathLabel.stringValue = shortPath(noteStore.folder)
        pathLabel.toolTip     = noteStore.folder.path
    }

    private func opacPercent(_ v: Double) -> String {
        "\(Int(v * 100))%"
    }

    // MARK: - Actions

    @objc private func startupToggled() {
        setLaunchAtStartup(startupCheckbox.state == .on)
    }

    @objc private func autoHideToggled() {
        UserDefaults.standard.set(autoHideCheckbox.state == .on,
                                   forKey: "typee.autoHideOnDeactivate")
    }

    @objc private func hotkeyChanged() {
        hotkeyManager.updateKey(HotkeyKey.allCases[hotkeyControl.selectedSegment])
    }

    @objc private func fontSliderChanged() {
        let size = fontSlider.doubleValue.rounded()
        fontValueLabel.stringValue = "\(Int(size)) pt"
        appDelegate?.applyFontSize(CGFloat(size))
    }

    @objc private func opacSliderChanged() {
        let v = opacSlider.doubleValue
        opacValueLabel.stringValue = opacPercent(v)
        appDelegate?.applyWindowOpacity(v)
    }

    @objc private func closeSelf() { window?.orderOut(nil) }

    @objc private func revealInFinder() {
        NSWorkspace.shared.selectFile(noteStore.notesFileURL.path,
                                      inFileViewerRootedAtPath: noteStore.folder.path)
    }

    @objc private func checkForUpdates() {
        checkUpdatesBtn.isEnabled = false
        checkUpdatesBtn.title = "Checking…"
        appDelegate?.checkForUpdates(silent: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.checkUpdatesBtn.isEnabled = true
            self?.checkUpdatesBtn.title = "Check for Updates"
        }
    }

    @objc private func changeNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles       = false
        panel.canCreateDirectories = true
        panel.prompt               = "Select Folder"
        panel.message              = "Choose where Typee saves your notes."
        guard let win = self.window else { return }
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard url != self.noteStore.folder else { return }
            let existingFile = url.appendingPathComponent("notes.json")
            if FileManager.default.fileExists(atPath: existingFile.path) {
                self.askImportOrOverwrite(newFolder: url)
            } else {
                self.noteStore.switchFolder(to: url, copyCurrentNotes: true)
                self.updatePathDisplay()
            }
        }
    }

    private func askImportOrOverwrite(newFolder: URL) {
        guard let win = self.window else { return }
        let alert = NSAlert()
        alert.messageText     = "This folder already contains notes"
        alert.informativeText = "Import those notes, or save your current notes here instead?"
        alert.addButton(withTitle: "Import Existing Notes")
        alert.addButton(withTitle: "Keep Current Notes")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: win) { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .alertFirstButtonReturn:  self.noteStore.switchFolder(to: newFolder, copyCurrentNotes: false)
            case .alertSecondButtonReturn: self.noteStore.switchFolder(to: newFolder, copyCurrentNotes: true)
            default: return
            }
            self.updatePathDisplay()
        }
    }

    // MARK: - Launch at startup

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.typee.app.plist")
    }

    private var launchAtStartupEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func setLaunchAtStartup(_ on: Bool) {
        if on {
            let exec = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
                <key>Label</key><string>com.typee.app</string>
                <key>ProgramArguments</key><array><string>\(exec)</string></array>
                <key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? xml.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
    }
}
