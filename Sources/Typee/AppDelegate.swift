import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var typeeWindow: TypeeWindow!
    private var noteStore: NoteStore!
    private var originApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        noteStore    = NoteStore()
        typeeWindow  = TypeeWindow(noteStore: noteStore)
        typeeWindow.onWillHide = { [weak self] in self?.originApp = nil }

        buildMainMenu()
        setupStatusItem()
        setupHotkey()
        setupWorkspaceObserver()
    }

    // NSApp.sendEvent: checks mainMenu key equivalents before dispatching to the
    // first responder. Without these items, Cmd+A/C/V never reach NSTextView even
    // though it handles them natively.
    private func buildMainMenu() {
        let bar = NSMenu()

        // ── App (required first item) ──────────────────────────────────────
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Typee",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu

        // ── Edit ───────────────────────────────────────────────────────────
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
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Typee",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onDoubleTap = { [weak self] in self?.toggleTypee() }
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

        // First non-Typee, non-Finder app after showing becomes Main App.
        // Typee only hides via Escape or Cmd+W — never automatically on app switch.
        if originApp == nil && !isFinder {
            originApp = app
        }
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
}
