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

        setupStatusItem()
        setupHotkey()
        setupWorkspaceObserver()
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
        // Ignore our own app activating
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let isFinder = app.bundleIdentifier == "com.apple.finder"

        // First non-Typee app after showing: set as origin (never hide on first switch)
        // Finder is allowed but never becomes the origin — the origin is the first real work app.
        if originApp == nil {
            if !isFinder { originApp = app }
            return
        }

        let isOrigin = app.bundleIdentifier == originApp?.bundleIdentifier
        if !isOrigin && !isFinder {
            typeeWindow.hide()
            originApp = nil
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
