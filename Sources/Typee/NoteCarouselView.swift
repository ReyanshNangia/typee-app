import AppKit

final class NoteCarouselView: NSView {
    var onCreateNote: (() -> Void)?
    var onPageChanged: ((Int) -> Void)?

    private let noteStore: NoteStore
    private var scrollViews: [NSScrollView] = []
    private var textViews: [NSTextView] = []

    private var container: NSView!
    private var ghostView: NSView!
    private(set) var currentPage: Int = 0
    private var displayOffset: CGFloat = 0

    // MARK: - Drag state

    private enum Axis { case none, horizontal, vertical }
    private var gestureAxis  = Axis.none
    private var dragStart    = CGFloat(0)  // displayOffset at gesture begin
    private var dragPage     = 0           // currentPage at gesture begin
    private var recentDeltas = [(t: CFTimeInterval, dx: CGFloat)]()
    private var elasticOver  = CGFloat(0)  // right-edge overscroll amount

    // MARK: - Spring animation

    private var springPos: CGFloat = 0
    private var springVel: CGFloat = 0
    private var springTarget: CGFloat = 0
    private var animTimer: Timer?

    // MARK: - Init

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        container = NSView()
        container.wantsLayer = true
        addSubview(container)

        ghostView = makeGhost()
        container.addSubview(ghostView)
        ghostView.alphaValue = 0

        for note in noteStore.notes { addPage(note: note) }
        currentPage = noteStore.activeIndex
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Page management

    /// Called when a new note has been added to the store.
    func appendNewPage(animated: Bool) {
        let note = noteStore.notes.last!
        addPage(note: note)

        let newIdx = scrollViews.count - 1
        let w = bounds.width, h = bounds.height
        if w > 0 && h > 0 {
            container.frame.size.width = w * CGFloat(scrollViews.count)
            scrollViews[newIdx].frame = NSRect(x: CGFloat(newIdx) * w, y: 0, width: w, height: h)
            if let tv = scrollViews[newIdx].documentView as? NSTextView {
                tv.minSize = NSSize(width: 0, height: h)
                tv.frame   = NSRect(x: 0, y: 0, width: w, height: h)
            }
        }
        updateGhostFrame()

        if animated {
            // Spring with a little bounce so it feels like a new note popped in
            springJump(to: newIdx, stiffness: 320, damping: 20)
        }
    }

    private func addPage(note: Note) {
        let sv = NSScrollView()
        sv.hasVerticalScroller  = true
        sv.autohidesScrollers   = true
        sv.drawsBackground      = false
        sv.borderType           = .noBorder

        let tv = makeTextView()

        if let data = note.rtfData,
           let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attr)
        } else {
            tv.string = note.content
        }
        tv.delegate = self

        sv.documentView = tv
        scrollViews.append(sv)
        textViews.append(tv)
        container.addSubview(sv)
    }

    private func makeTextView() -> NSTextView {
        let tv = NSTextView()
        tv.isRichText           = true   // enables Cmd+B/I/U and text selection
        tv.allowsUndo           = true
        tv.usesFontPanel        = false
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask        = .width
        tv.textContainer?.widthTracksTextView  = true
        tv.textContainer?.heightTracksTextView = false
        tv.minSize   = NSSize(width: 0, height: bounds.height)
        tv.maxSize   = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        tv.font      = .systemFont(ofSize: 15)
        tv.textColor = .labelColor
        tv.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
        ]
        tv.drawsBackground  = false
        tv.isAutomaticQuoteSubstitutionEnabled   = false
        tv.isAutomaticDashSubstitutionEnabled    = false
        tv.isAutomaticSpellingCorrectionEnabled  = false
        tv.isGrammarCheckingEnabled              = false
        tv.textContainerInset = NSSize(width: 24, height: 20)
        return tv
    }

    private func makeGhost() -> NSView {
        let v = NSView()
        v.wantsLayer             = true
        v.layer?.borderColor     = NSColor.separatorColor.cgColor
        v.layer?.borderWidth     = 1.5
        v.layer?.cornerRadius    = 6

        let label = NSTextField(labelWithString: "+ New Note")
        label.font               = .systemFont(ofSize: 13, weight: .light)
        label.textColor          = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    func focusCurrent() {
        guard currentPage < textViews.count else { return }
        guard let win = window, win.isVisible else { return }
        win.makeFirstResponder(textViews[currentPage])
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }

        // On window resize: snap to current page unless animating
        if animTimer == nil {
            displayOffset = CGFloat(currentPage) * w
        }

        let count = max(1, scrollViews.count)
        container.frame = NSRect(x: -displayOffset, y: 0,
                                 width: w * CGFloat(count), height: h)
        for (i, sv) in scrollViews.enumerated() {
            sv.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            if let tv = sv.documentView as? NSTextView {
                tv.minSize = NSSize(width: 0, height: h)
                let tvH = max(h, tv.frame.height)
                if tv.frame.size != NSSize(width: w, height: tvH) {
                    tv.frame = NSRect(x: 0, y: 0, width: w, height: tvH)
                }
            }
        }
        updateGhostFrame()
    }

    private func updateGhostFrame() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let inset: CGFloat = 24
        ghostView.frame = NSRect(x: CGFloat(scrollViews.count) * w + inset,
                                 y: inset,
                                 width: w - inset * 2,
                                 height: h - inset * 2)
    }

    private func setOffset(_ offset: CGFloat) {
        displayOffset = offset
        container.frame.origin.x = -offset
    }

    // MARK: - Scroll interception (called from window-level monitor)

    /// Returns nil to consume the event, or the event to pass it through.
    func interceptScroll(_ event: NSEvent) -> NSEvent? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        // ── Gesture start ────────────────────────────────────────────────
        if event.phase == .began {
            gestureAxis = .none
            dragStart   = displayOffset
            dragPage    = currentPage
            elasticOver = 0
            recentDeltas.removeAll()
            stopAnim()
            ghostView.alphaValue = 0
        }

        // ── Axis lock ────────────────────────────────────────────────────
        if gestureAxis == .none {
            let adx = abs(dx), ady = abs(dy)
            if adx > 2 || ady > 2 {
                gestureAxis = (adx >= ady * 0.65) ? .horizontal : .vertical
            }
        }

        let isGesture  = !event.phase.isEmpty
        let isMomentum = !event.momentumPhase.isEmpty

        // ── Vertical: pass straight through to the scroll view ───────────
        if gestureAxis == .vertical {
            if isGesture && (event.phase == .ended || event.phase == .cancelled) {
                gestureAxis = .none
            }
            return event
        }

        // Pass through if we haven't determined the axis yet and have no movement
        if gestureAxis == .none && !isGesture && !isMomentum { return event }

        // ── Track for velocity ───────────────────────────────────────────
        if isGesture && event.phase == .changed {
            recentDeltas.append((CACurrentMediaTime(), dx))
            if recentDeltas.count > 8 { recentDeltas.removeFirst() }
        }

        // ── Apply finger movement ────────────────────────────────────────
        if isGesture && event.phase == .changed {
            applyDelta(dx)
        }
        // Discard momentum — we animate ourselves

        // ── Gesture end: settle ──────────────────────────────────────────
        if isGesture && (event.phase == .ended || event.phase == .cancelled) {
            gestureAxis = .none
            settle()
        }

        return nil  // consume horizontal events
    }

    // MARK: - Drag physics

    private func applyDelta(_ dx: CGFloat) {
        guard bounds.width > 0 else { return }
        let w = bounds.width
        let lastPage = max(0, scrollViews.count - 1)

        // One page at a time: hard-clamp the drag range to ±1 from gesture-start page
        let softMin = CGFloat(max(0,        dragPage - 1)) * w
        let softMax = CGFloat(min(lastPage, dragPage + 1)) * w

        let proposed = displayOffset - dx  // deltaX > 0 = go left = prev note

        if proposed < softMin {
            // Left hard stop (or elastic at absolute left edge)
            if dragPage == 0 {
                setOffset(softMin + rubberBand(proposed - softMin, band: w))
            } else {
                setOffset(softMin)
            }
            elasticOver = 0

        } else if proposed > softMax {
            // Right hard stop or elastic (for new-note overscroll at last page)
            if dragPage == lastPage {
                let over = proposed - softMax
                elasticOver = over
                let alpha = min(over / (w * 0.30), 1.0)
                ghostView.alphaValue = alpha
                setOffset(softMax + rubberBand(over, band: w))
            } else {
                setOffset(softMax)
                elasticOver = 0
            }

        } else {
            setOffset(proposed)
            elasticOver = 0
            ghostView.alphaValue = 0
        }
    }

    private func rubberBand(_ x: CGFloat, band: CGFloat) -> CGFloat {
        let abs_x = abs(x)
        let c     = band * 0.55
        let y     = (1.0 - 1.0 / (abs_x / c + 1.0)) * c
        return x < 0 ? -y : y
    }

    // MARK: - Settle

    private func settle() {
        let w = bounds.width
        guard w > 0 else { return }

        ghostView.alphaValue = 0

        // New note creation via right overscroll
        if elasticOver > w * 0.30 {
            elasticOver = 0
            onCreateNote?()
            return
        }

        elasticOver = 0

        let delta = displayOffset - dragStart  // > 0 = swiped left = next note
        let vel   = estimatedVelocity()        // > 0 = moving next, < 0 = moving prev

        let posThreshold: CGFloat = w * 0.20
        let velThreshold: CGFloat = 250

        var target = currentPage

        if delta < -posThreshold || vel < -velThreshold {
            // Swiped toward previous
            target = max(0, currentPage - 1)
        } else if delta > posThreshold || vel > velThreshold {
            // Swiped toward next
            target = min(scrollViews.count - 1, currentPage + 1)
        }

        springJump(to: target, stiffness: 420, damping: 30)
    }

    private func estimatedVelocity() -> CGFloat {
        guard recentDeltas.count >= 2 else { return 0 }
        let recent = Array(recentDeltas.suffix(5))
        let totalDx = recent.map(\.dx).reduce(0, +)
        let dt = recent.last!.t - recent.first!.t
        guard dt > 0.001 else { return 0 }
        return -totalDx / dt   // positive = moving toward next page
    }

    // MARK: - Spring animation

    private func springJump(to page: Int, stiffness: CGFloat, damping: CGFloat) {
        let target = max(0, min(scrollViews.count - 1, page))

        if target != currentPage {
            currentPage = target
            onPageChanged?(target)
        }

        let targetOffset = CGFloat(target) * bounds.width
        startSpring(to: targetOffset, stiffness: stiffness, damping: damping)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.focusCurrent()
        }
    }

    private func startSpring(to targetOff: CGFloat, stiffness: CGFloat, damping: CGFloat) {
        stopAnim()
        springPos    = displayOffset
        springVel    = 0
        springTarget = targetOff

        let k = stiffness, b = damping, m = CGFloat(1.0)

        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0,
                                         repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }

            let dt: CGFloat = 1.0 / 120.0
            let force      = k * (self.springTarget - self.springPos)
            let damp       = b * self.springVel
            let accel      = (force - damp) / m

            self.springVel += accel * dt
            self.springPos += self.springVel * dt
            self.setOffset(self.springPos)

            if abs(self.springPos - self.springTarget) < 0.4
               && abs(self.springVel) < 0.5 {
                self.setOffset(self.springTarget)
                t.invalidate()
                self.animTimer = nil
            }
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func stopAnim() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - NSTextViewDelegate

extension NoteCarouselView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv    = notification.object as? NSTextView,
              let idx   = textViews.firstIndex(of: tv),
              let store = tv.textStorage else { return }
        let range   = NSRange(location: 0, length: store.length)
        let rtf     = store.rtf(from: range, documentAttributes: [:])
        noteStore.updateNote(at: idx, content: tv.string, rtfData: rtf)
    }
}
