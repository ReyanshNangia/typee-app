import AppKit
import Darwin

private let activateNotification = Notification.Name("com.typee.app.activate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var typeeWindow: TypeeWindow!
    private var noteStore: NoteStore!
    private var originApp: NSRunningApplication?
    private var settingsController: SettingsWindowController?
    private var lockFD: Int32 = -1
    private(set) var availableUpdate: String? = nil  // set when a newer version is found

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            DistributedNotificationCenter.default().postNotificationName(
                activateNotification, object: nil, userInfo: nil,
                deliverImmediately: true)
            exit(0)
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(bringToFront),
            name: activateNotification, object: nil,
            suspensionBehavior: .deliverImmediately)

        noteStore = NoteStore()
        setupWelcomeNote()
        typeeWindow  = TypeeWindow(noteStore: noteStore)
        typeeWindow.onWillHide = { [weak self] in self?.originApp = nil }

        buildMainMenu()
        setupStatusItem()
        setupHotkey()
        setupWorkspaceObserver()
        setupAutoHideObserver()

        // Check for updates in the background after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
    }

    // MARK: - Welcome note

    private func setupWelcomeNote() {
        let key = "typee.hasSeenWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard noteStore.notes.count == 1, noteStore.notes[0].content.isEmpty else { return }

        let attr = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat = 15, weight: NSFont.Weight = .regular,
                 color: NSColor = .labelColor) {
            attr.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
            ]))
        }

        add("Welcome to Typee\n", size: 17, weight: .semibold)
        add("\n")
        add("A fast, floating notepad that lives in your menu bar.\n", size: 14,
            color: .secondaryLabelColor)
        add("\n")
        add("Getting started\n", size: 14, weight: .medium)
        add("Double-tap  ⌃  (or ⌥ or ⌘) to show and hide this window.\n")
        add("⌘N  ")
        add("new note", weight: .medium)
        add("   ⌘W  ")
        add("hide", weight: .medium)
        add("   Esc  ")
        add("hide\n", weight: .medium)
        add("Swipe left or right to navigate between notes.\n")
        add("\n")
        add("Formatting\n", size: 14, weight: .medium)
        add("⌘B  bold   ⌘U  underline\n")
        add("⌘=  bigger text   ⌘−  smaller text\n")
        add("Type  ")
        add("1. ", weight: .medium)
        add("or  ")
        add("a. ", weight: .medium)
        add("then Space to start a list.\n")
        add("\n")
        add("Click the palette icon at the bottom to add colour to this note.\n",
            size: 13, color: .secondaryLabelColor)
        add("\n")
        add("Delete this note when you're ready — ⌘⇧N", size: 13,
            color: .tertiaryLabelColor)

        let range = NSRange(location: 0, length: attr.length)
        let rtf = attr.rtf(from: range, documentAttributes: [:])
        noteStore.updateNote(at: 0, content: attr.string, rtfData: rtf)
    }

    // MARK: - Auto-hide on deactivate

    private func setupAutoHideObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func appDidResignActive() {
        guard UserDefaults.standard.bool(forKey: "typee.autoHideOnDeactivate") else { return }
        guard typeeWindow?.isVisible == true else { return }
        typeeWindow.hide()
    }

    // MARK: - Update check

    func checkForUpdates(silent: Bool) {
        guard let urlString = kUpdateCheckURL, let url = URL(string: urlString) else {
            if !silent {
                showUpdateAlert(title: "No update URL configured",
                                message: "Set kUpdateCheckURL in AppVersion.swift to enable update checks.")
            }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let latest = json["version"] else {
                if !silent {
                    DispatchQueue.main.async {
                        self.showUpdateAlert(title: "Could not check for updates",
                                             message: "Make sure you're connected to the internet.")
                    }
                }
                return
            }
            DispatchQueue.main.async {
                if latest.compare(kAppVersion, options: .numeric) == .orderedDescending {
                    self.availableUpdate = latest
                    self.rebuildStatusMenu()
                    if !silent {
                        let url = json["url"].flatMap { URL(string: $0) }
                        self.showUpdateAlert(title: "Update available — v\(latest)",
                                             message: "You're on v\(kAppVersion).",
                                             downloadURL: url)
                    }
                } else if !silent {
                    self.showUpdateAlert(title: "You're up to date",
                                         message: "Typee \(kAppVersion) is the latest version.")
                }
            }
        }.resume()
    }

    private func showUpdateAlert(title: String, message: String, downloadURL: URL? = nil) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        if let url = downloadURL {
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Single-instance lock

    private func acquireSingleInstanceLock() -> Bool {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
                      .appendingPathComponent("Typee")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(".lock").path
        lockFD = open(path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else { return true }          // can't create lock → assume we're alone
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0   // non-blocking exclusive lock
    }

    @objc private func bringToFront() {
        DispatchQueue.main.async { [weak self] in
            self?.typeeWindow.show()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Main menu (required for Cmd+A/C/V to reach NSTextView)

    private func buildMainMenu() {
        let bar = NSMenu()

        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Typee",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit

        NSApp.mainMenu = bar
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Typee")
            button.image?.isTemplate = true
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        // Update available badge
        if let v = availableUpdate {
            let upd = NSMenuItem(title: "Update Available — v\(v)",
                                 action: #selector(menuOpenUpdate),
                                 keyEquivalent: "")
            upd.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                accessibilityDescription: nil)
            menu.addItem(upd)
            menu.addItem(.separator())
        }

        // Accessibility prompt
        if !(hotkeyManager?.isTrusted ?? true) {
            let ax = NSMenuItem(title: "Enable Global Hotkey…",
                                action: #selector(menuEnableHotkey),
                                keyEquivalent: "")
            ax.image = NSImage(systemSymbolName: "hand.raised",
                               accessibilityDescription: nil)
            menu.addItem(ax)
            menu.addItem(.separator())
        }

        let newNote = NSMenuItem(title: "New Note",
                                 action: #selector(menuNewNote),
                                 keyEquivalent: "")
        newNote.image = NSImage(systemSymbolName: "square.and.pencil",
                                accessibilityDescription: nil)
        menu.addItem(newNote)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(menuSettings),
                                  keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape",
                                 accessibilityDescription: nil)
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Typee",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func menuNewNote() {
        if !typeeWindow.isVisible {
            originApp = nil
            typeeWindow.show()
        }
        typeeWindow.createNote()
    }

    @objc private func menuSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(appDelegate: self,
                                                          hotkeyManager: hotkeyManager,
                                                          noteStore: noteStore)
        }
        settingsController?.show()
    }

    @objc private func menuOpenUpdate() {
        // Open the update URL if we have one cached, otherwise launch the check
        checkForUpdates(silent: false)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onDoubleTap = { [weak self] in self?.toggleTypee() }
        hotkeyManager.onTrustGained = { [weak self] in
            DispatchQueue.main.async { self?.rebuildStatusMenu() }
        }
        // Rebuild now that hotkeyManager exists — shows "Enable Global Hotkey…" if not trusted
        rebuildStatusMenu()
    }

    @objc private func menuEnableHotkey() {
        hotkeyManager.promptForAccessibility()
    }

    // MARK: - Origin-app tracking

    private func setupWorkspaceObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeAppChanged(_ notification: Notification) {
        guard typeeWindow.isVisible else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let isFinder = app.bundleIdentifier == "com.apple.finder"
        if originApp == nil && !isFinder { originApp = app }
    }

    // MARK: - Toggle

    private func toggleTypee() {
        if typeeWindow.isVisible {
            typeeWindow.hide()
        } else {
            originApp = nil
            typeeWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteStore?.persist()   // flush any pending 0.3 s save timer
    }

    // MARK: - Settings callbacks

    func applyFontSize(_ size: CGFloat) {
        typeeWindow.setDefaultFontSize(size)
    }

    func applyWindowOpacity(_ v: Double) {
        typeeWindow.applyOpacity(v)
    }
}
