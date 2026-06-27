import AppKit

final class TypeeWindow: NSPanel {
    var onWillHide: (() -> Void)?

    private let noteStore: NoteStore
    private var carousel:     NoteCarouselView!
    private var indicator:    PageIndicatorView!
    private var colorOverlay: NSView!
    private var brushButton:  NSButton!
    private var colorPopover: NSPopover!
    private var pickerView:   ColorPickerView!
    private var countLabel:    NSTextField!
    private var keyMonitor:   Any?
    private var scrollMonitor: Any?

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.carousel.focusCurrent()
            self.syncColor(animated: false)
        }
    }

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
        setupColorPopover()
    }

    private static func savedSize() -> NSSize {
        if let data = UserDefaults.standard.data(forKey: "typee.windowSize"),
           let s = try? JSONDecoder().decode(CGSize.self, from: data) {
            return NSSize(width: max(300, s.width), height: max(200, s.height))
        }
        return NSSize(width: 480, height: 360)
    }

    private func configure() {
        titleVisibility             = .hidden
        titlebarAppearsTransparent  = true
        isMovableByWindowBackground = true
        level                       = .floating
        hidesOnDeactivate           = false
        collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize                     = NSSize(width: 300, height: 200)
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = true
        animationBehavior           = .none
        self.delegate               = self

        standardWindowButton(.closeButton)?.isHidden       = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden        = false
    }

    // MARK: - UI

    private func buildUI() {
        let blur = NSVisualEffectView()
        blur.material     = .sidebar
        blur.blendingMode = .behindWindow
        blur.state        = .active
        blur.wantsLayer   = true
        blur.layer?.cornerRadius  = 12
        blur.layer?.masksToBounds = true

        // Full-window color overlay — sits below all content
        colorOverlay = NSView()
        colorOverlay.wantsLayer = true
        colorOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        colorOverlay.translatesAutoresizingMaskIntoConstraints = false

        noteStore.onReloaded = { [weak self] in self?.reloadNotes() }

        carousel = NoteCarouselView(noteStore: noteStore)
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.onCreateNote  = { [weak self] in self?.handleCreateNote() }
        carousel.onPageChanged = { [weak self] idx in
            guard let self else { return }
            self.noteStore.setActiveIndex(idx)
            self.indicator.moveTo(idx)
            self.syncColor(animated: true)
            self.carousel.updateStatsForCurrentPage()
        }

        carousel.onStatsChanged = { [weak self] words, chars in
            DispatchQueue.main.async { self?.updateCountLabel(words: words, chars: chars) }
        }

        indicator = PageIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.reload(count: noteStore.notes.count,
                         current: noteStore.activeIndex)
        indicator.onPageSelected = { [weak self] idx in
            self?.carousel.navigateTo(idx)
        }
        indicator.onReorder = { [weak self] from, to in
            guard let self else { return }
            self.noteStore.moveNote(from: from, to: to)
            self.carousel.reorderPage(from: from, to: to)
            self.indicator.reload(count: self.noteStore.notes.count,
                                  current: self.carousel.currentPage)
        }

        // Brush button — bottom right of indicator bar
        brushButton = NSButton()
        brushButton.image = NSImage(systemSymbolName: "paintpalette.fill",
                                    accessibilityDescription: "Note color")
        brushButton.imageScaling = .scaleProportionallyDown
        brushButton.bezelStyle   = .inline
        brushButton.isBordered   = false
        brushButton.image?.isTemplate = true
        brushButton.contentTintColor  = .tertiaryLabelColor
        brushButton.alphaValue   = 0.75
        brushButton.target       = self
        brushButton.action       = #selector(toggleColorPicker(_:))
        brushButton.translatesAutoresizingMaskIntoConstraints = false

        countLabel = NSTextField(labelWithString: "")
        countLabel.font      = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        // Add in z-order: overlay first (behind), content on top
        blur.addSubview(colorOverlay)
        blur.addSubview(carousel)
        blur.addSubview(indicator)
        blur.addSubview(brushButton)
        blur.addSubview(countLabel)

        NSLayoutConstraint.activate([
            // Color overlay fills the entire window
            colorOverlay.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            colorOverlay.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            colorOverlay.topAnchor.constraint(equalTo: blur.topAnchor),
            colorOverlay.bottomAnchor.constraint(equalTo: blur.bottomAnchor),

            // Carousel
            carousel.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            carousel.topAnchor.constraint(equalTo: blur.topAnchor, constant: 28),
            carousel.bottomAnchor.constraint(equalTo: indicator.topAnchor),

            // Indicator bar (full width so dots center correctly)
            indicator.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            indicator.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            indicator.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            indicator.heightAnchor.constraint(equalToConstant: 24),

            // Brush button — right side of indicator bar
            brushButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
            brushButton.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
            brushButton.widthAnchor.constraint(equalToConstant: 16),
            brushButton.heightAnchor.constraint(equalToConstant: 16),

            // Count label — left side of indicator bar
            countLabel.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
        ])

        contentView = blur
    }

    // MARK: - Color popover

    private func setupColorPopover() {
        let swatchD: CGFloat = 22
        let swatchG: CGFloat = 10
        pickerView = ColorPickerView(diameter: swatchD, gap: swatchG)
        pickerView.onColorSelected = { [weak self] name in
            guard let self else { return }
            let page = self.carousel.currentPage
            self.noteStore.updateColor(at: page, colorName: name)
            self.applyWindowColor(name, animated: true)
        }

        let padding: CGFloat = 14
        let pw = pickerView.preferredWidth
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: pw + 2 * padding,
                                             height: swatchD + 2 * padding))
        pickerView.frame = NSRect(x: padding, y: padding, width: pw, height: swatchD)
        container.addSubview(pickerView)

        let vc = NSViewController()
        vc.view = container

        colorPopover = NSPopover()
        colorPopover.contentViewController = vc
        colorPopover.behavior = .transient
        colorPopover.animates = true
    }

    @objc private func toggleColorPicker(_ sender: NSButton) {
        if colorPopover.isShown {
            colorPopover.close()
            return
        }
        let page = carousel.currentPage
        let name = page < noteStore.notes.count ? noteStore.notes[page].colorName : nil
        pickerView.select(name)
        colorPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: - Color application

    private func applyWindowColor(_ colorName: String?, animated: Bool) {
        let color = NoteColor.background(named: colorName) ?? .clear
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.28)
            colorOverlay.layer?.backgroundColor = color.cgColor
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            colorOverlay.layer?.backgroundColor = color.cgColor
            CATransaction.commit()
        }
        carousel.setScrollerTint(NoteColor.background(named: colorName))
    }

    private func syncColor(animated: Bool) {
        let page = carousel.currentPage
        guard page < noteStore.notes.count else { return }
        applyWindowColor(noteStore.notes[page].colorName, animated: animated)
    }

    // MARK: - Notes

    private func handleCreateNote() {
        noteStore.addNote()
        carousel.appendNewPage(animated: true)
        indicator.reload(count: noteStore.notes.count,
                         current: noteStore.activeIndex)
        syncColor(animated: true)
    }

    func createNote() {
        handleCreateNote()
    }

    func reloadNotes() {
        carousel.reload()
        indicator.reload(count: noteStore.notes.count, current: noteStore.activeIndex)
        syncColor(animated: false)
        carousel.focusCurrent()
    }

    private func navigateNote(by delta: Int) {
        let target = carousel.currentPage + delta
        guard target >= 0, target < noteStore.notes.count else { return }
        carousel.navigateTo(target)
    }

    private func handleDeleteNote() {
        guard noteStore.notes.count > 1 else { return }
        noteStore.deleteNote(at: noteStore.activeIndex)
        carousel.deleteCurrentPage()
        noteStore.setActiveIndex(carousel.currentPage)
        indicator.reload(count: noteStore.notes.count,
                         current: carousel.currentPage)
        syncColor(animated: true)
    }

    // MARK: - Size persistence

    override func setContentSize(_ aSize: NSSize) {
        super.setContentSize(aSize)
        persistSize()
    }

    private func persistSize() {
        let s = CGSize(width: frame.width, height: frame.height)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: "typee.windowSize")
        }
    }

    // MARK: - Event monitors

    private func installMonitors() {
        removeMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.hide(); return nil }
            guard event.modifierFlags.contains(.command) else { return event }
            let isShift = event.modifierFlags.contains(.shift)
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w": self.hide(); return nil
            case "n":
                if isShift { self.handleDeleteNote() }
                else       { self.handleCreateNote() }
                return nil
            case "b": self.carousel.toggleBold();      return nil
            case "u": self.carousel.toggleUnderline(); return nil
            case "[": self.navigateNote(by: -1);       return nil
            case "]": self.navigateNote(by: +1);       return nil
            case "v":
                if isShift {
                    // Paste as plain text (strip all formatting)
                    if let tv = self.carousel.currentTextView,
                       let str = NSPasteboard.general.string(forType: .string) {
                        tv.insertText(str as NSString, replacementRange: tv.selectedRange())
                    }
                    return nil
                }
                return event
            case "=":
                self.carousel.adjustSelectionFontSize(by: +1)
                return nil
            case "-":
                self.carousel.adjustSelectionFontSize(by: -1)
                return nil
            default:  return event
            }
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
        let opacity = { () -> Double in
            let v = UserDefaults.standard.double(forKey: "typee.windowOpacity")
            return v > 0 ? v : 1.0
        }()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = opacity
        } completionHandler: {
            self.alphaValue = opacity
        }
    }

    func hide() {
        noteStore.persist()
        onWillHide?()
        colorPopover.close()
        removeMonitors()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            let savedOpacity = UserDefaults.standard.double(forKey: "typee.windowOpacity")
            self.alphaValue = savedOpacity > 0 ? savedOpacity : 1.0
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

    // MARK: - Public settings hooks

    func applyOpacity(_ v: Double) {
        let clamped = max(0.2, min(1.0, v))
        UserDefaults.standard.set(clamped, forKey: "typee.windowOpacity")
        if isVisible { alphaValue = clamped }
    }

    func setDefaultFontSize(_ size: CGFloat) {
        carousel.setDefaultFontSize(size)
    }

    private func updateCountLabel(words: Int, chars: Int) {
        countLabel.stringValue = (words == 0 && chars == 0) ? "" : "\(words)w · \(chars)c"
    }
}

// MARK: - NSWindowDelegate

extension TypeeWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
