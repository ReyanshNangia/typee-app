import AppKit

final class TypeeWindow: NSPanel {
    var onWillHide: (() -> Void)?

    private let noteStore: NoteStore
    private var carousel: NoteCarouselView!
    private var indicator: PageIndicatorView!
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    private let sizeKey = "typee.windowSize"

    // MARK: - Init

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        let size = TypeeWindow.savedSize()
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configure()
        buildUI()
    }

    private static func savedSize() -> NSSize {
        if let data = UserDefaults.standard.data(forKey: "typee.windowSize"),
           let s = try? JSONDecoder().decode(CGSize.self, from: data) {
            return NSSize(width: max(300, s.width), height: max(200, s.height))
        }
        return NSSize(width: 480, height: 360)
    }

    private func configure() {
        titleVisibility            = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level                      = .floating
        collectionBehavior         = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize                    = NSSize(width: 300, height: 200)
        isOpaque                   = false
        backgroundColor            = .clear
        hasShadow                  = true
        animationBehavior          = .none
        self.delegate              = self

        // Ensure all three traffic lights are visible
        standardWindowButton(.closeButton)?.isHidden      = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden       = false
    }

    // MARK: - UI

    private func buildUI() {
        let blur = NSVisualEffectView()
        blur.material     = .sidebar
        blur.blendingMode = .behindWindow
        blur.state        = .active
        blur.wantsLayer   = true
        blur.layer?.cornerRadius    = 12
        blur.layer?.masksToBounds   = true

        carousel = NoteCarouselView(noteStore: noteStore)
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.onCreateNote  = { [weak self] in self?.handleCreateNote() }
        carousel.onPageChanged = { [weak self] idx in
            self?.noteStore.setActiveIndex(idx)
            self?.indicator.moveTo(idx)
        }

        indicator = PageIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.reload(count: noteStore.notes.count,
                         current: noteStore.activeIndex)

        blur.addSubview(carousel)
        blur.addSubview(indicator)

        NSLayoutConstraint.activate([
            carousel.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            carousel.topAnchor.constraint(equalTo: blur.topAnchor, constant: 28),
            carousel.bottomAnchor.constraint(equalTo: indicator.topAnchor),

            indicator.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            indicator.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            indicator.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            indicator.heightAnchor.constraint(equalToConstant: 24),
        ])

        contentView = blur
    }

    // MARK: - Notes

    private func handleCreateNote() {
        noteStore.addNote()
        carousel.appendNewPage(animated: true)
        indicator.reload(count: noteStore.notes.count,
                         current: noteStore.activeIndex)
    }

    // MARK: - Size persistence

    override func setContentSize(_ aSize: NSSize) {
        super.setContentSize(aSize)
        persistSize()
    }

    private func persistSize() {
        let s = CGSize(width: frame.width, height: frame.height)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: sizeKey)
        }
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Escape
            if event.keyCode == 53 { self.hide(); return nil }
            // Cmd-N
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "n" {
                self.handleCreateNote(); return nil
            }
            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isVisible, event.window === self else { return event }
            return self.carousel.interceptScroll(event)
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor    { NSEvent.removeMonitor(m); keyMonitor    = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    // MARK: - Show / Hide

    func show() {
        positionNearCursor()
        alphaValue = 0
        installMonitors()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Defer focus so the window is fully on screen first
        DispatchQueue.main.async { [weak self] in self?.carousel.focusCurrent() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        noteStore.persist()
        onWillHide?()
        removeMonitors()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }

    // MARK: - Positioning

    private func positionNearCursor() {
        let mouse = NSEvent.mouseLocation
        let w = frame.width, h = frame.height
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        var o  = NSPoint(x: mouse.x - w / 2, y: mouse.y - h / 2)
        o.x = max(sf.minX + 16, min(o.x, sf.maxX - w - 16))
        o.y = max(sf.minY + 16, min(o.y, sf.maxY - h - 16))
        setFrameOrigin(o)
    }
}

// MARK: - NSWindowDelegate

extension TypeeWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
