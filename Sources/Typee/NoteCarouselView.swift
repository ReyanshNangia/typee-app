import AppKit

final class NoteCarouselView: NSView {
    var onCreateNote: (() -> Void)?
    var onPageChanged: ((Int) -> Void)?

    private let noteStore: NoteStore
    private var scrollViews: [NSScrollView] = []
    private var textViews: [NSTextView] = []

    private var container: NSView!
    private(set) var currentPage: Int = 0
    private var displayOffset: CGFloat = 0

    // Gesture state
    private enum Axis { case none, horizontal, vertical }
    private var gestureAxis = Axis.none
    private var gestureStartOffset: CGFloat = 0
    private var elasticOverscroll: CGFloat = 0
    private var recentDeltas = [(t: CFTimeInterval, dx: CGFloat)]()

    private var animTimer: Timer?

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        container = NSView()
        container.wantsLayer = true
        addSubview(container)

        for note in noteStore.notes {
            buildPage(content: note.content)
        }
        currentPage = noteStore.activeIndex
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Page management

    func appendPage(content: String, animated: Bool) {
        buildPage(content: content)
        let newIdx = scrollViews.count - 1
        // Layout the new page without snapping display offset
        let w = bounds.width, h = bounds.height
        if w > 0 && h > 0 {
            container.frame.size.width = w * CGFloat(scrollViews.count)
            let sv = scrollViews[newIdx]
            sv.frame = NSRect(x: CGFloat(newIdx) * w, y: 0, width: w, height: h)
            if let tv = sv.documentView as? NSTextView {
                tv.minSize = NSSize(width: 0, height: h)
                tv.frame = NSRect(x: 0, y: 0, width: w, height: h)
            }
        }
        if animated { animateTo(page: newIdx) }
    }

    private func buildPage(content: String) {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder

        let tv = NSTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = .width
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.minSize = NSSize(width: 0, height: bounds.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.string = content
        tv.delegate = self

        sv.documentView = tv
        scrollViews.append(sv)
        textViews.append(tv)
        container.addSubview(sv)
    }

    func focusCurrent() {
        guard currentPage < textViews.count else { return }
        window?.makeFirstResponder(textViews[currentPage])
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        guard w > 0 && h > 0 else { return }

        // On resize, snap offset to current page (no animation running)
        if animTimer == nil {
            displayOffset = CGFloat(currentPage) * w
        }

        container.frame = NSRect(x: -displayOffset, y: 0,
                                 width: w * CGFloat(max(1, scrollViews.count)), height: h)

        for (i, sv) in scrollViews.enumerated() {
            sv.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            if let tv = sv.documentView as? NSTextView {
                tv.minSize = NSSize(width: 0, height: h)
                let tvH = max(h, tv.frame.height)
                if tv.frame != NSRect(x: 0, y: 0, width: w, height: tvH) {
                    tv.frame = NSRect(x: 0, y: 0, width: w, height: tvH)
                }
            }
        }
    }

    private func setDisplayOffset(_ offset: CGFloat) {
        displayOffset = offset
        container.frame.origin.x = -offset
    }

    // MARK: - Scroll interception

    /// Called from TypeeWindow's local scroll monitor. Returns nil to consume, event to pass through.
    func interceptScroll(_ event: NSEvent) -> NSEvent? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.phase == .began {
            gestureAxis = .none
            gestureStartOffset = displayOffset
            elasticOverscroll = 0
            recentDeltas.removeAll()
            cancelAnim()
        }

        // Axis lock: give horizontal a slight preference (0.7 factor)
        if gestureAxis == .none {
            let adx = abs(dx), ady = abs(dy)
            if adx > 2 || ady > 2 {
                gestureAxis = adx >= ady * 0.7 ? .horizontal : .vertical
            }
        }

        let isGesture  = !event.phase.isEmpty
        let isMomentum = !event.momentumPhase.isEmpty

        // Vertical: pass through to the underlying NSScrollView
        if gestureAxis == .vertical {
            if isGesture && (event.phase == .ended || event.phase == .cancelled) {
                gestureAxis = .none
            }
            return event
        }

        // Unknown axis with no movement yet: pass through
        if gestureAxis == .none && !isGesture && !isMomentum {
            return event
        }

        // Track deltas for velocity estimation
        if isGesture && event.phase == .changed {
            recentDeltas.append((CACurrentMediaTime(), dx))
            if recentDeltas.count > 6 { recentDeltas.removeFirst() }
        }

        // Apply movement
        if (isGesture && event.phase == .changed) ||
           (isMomentum && event.momentumPhase == .changed) {
            applyDelta(dx)
        }

        // Settle on gesture or momentum end
        let gestureEnded  = isGesture  && (event.phase == .ended || event.phase == .cancelled)
        let momentumEnded = isMomentum && (event.momentumPhase == .ended || event.momentumPhase == .cancelled)

        if gestureEnded || momentumEnded {
            if gestureEnded { gestureAxis = .none }
            settle()
        }

        return nil
    }

    private func applyDelta(_ dx: CGFloat) {
        guard bounds.width > 0 else { return }
        let w = bounds.width
        let maxOff = CGFloat(max(0, scrollViews.count - 1)) * w
        let proposed = displayOffset - dx

        if proposed < 0 {
            elasticOverscroll = 0
            setDisplayOffset(rubberBand(proposed, range: w))
        } else if proposed > maxOff {
            let over = proposed - maxOff
            elasticOverscroll = over
            setDisplayOffset(maxOff + rubberBand(over, range: w))
        } else {
            elasticOverscroll = 0
            setDisplayOffset(proposed)
        }
    }

    private func rubberBand(_ x: CGFloat, range: CGFloat) -> CGFloat {
        let abs_x = abs(x)
        let c = range * 0.55
        let stretched = (1.0 - 1.0 / (abs_x / c + 1.0)) * c
        return x < 0 ? -stretched : stretched
    }

    private func settle() {
        let w = bounds.width
        guard w > 0 else { return }

        // New note creation via right overscroll
        if elasticOverscroll > w * 0.28 {
            elasticOverscroll = 0
            onCreateNote?()
            return
        }

        // Snap to nearest page with velocity bias
        let rawPage = displayOffset / w
        let vel = estimateVelocity()
        let bias = (vel / w) * 0.12
        var target = Int((rawPage + bias).rounded())
        target = max(0, min(scrollViews.count - 1, target))
        animateTo(page: target)
        elasticOverscroll = 0
    }

    private func estimateVelocity() -> CGFloat {
        guard recentDeltas.count >= 2 else { return 0 }
        let recent = Array(recentDeltas.suffix(4))
        let totalDx = recent.map { $0.dx }.reduce(0, +)
        let dt = recent.last!.t - recent.first!.t
        guard dt > 0.001 else { return 0 }
        return -totalDx / dt
    }

    private func animateTo(page: Int) {
        currentPage = max(0, min(scrollViews.count - 1, page))
        onPageChanged?(currentPage)
        animateOffset(to: CGFloat(currentPage) * bounds.width)
        // Focus after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusCurrent()
        }
    }

    private func animateOffset(to target: CGFloat) {
        cancelAnim()
        let start = displayOffset
        let startTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.26

        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let p = CGFloat(min((CACurrentMediaTime() - startTime) / duration, 1.0))
            let e = 1.0 - pow(1.0 - p, 3.0)
            self.setDisplayOffset(start + (target - start) * e)
            if p >= 1.0 {
                t.invalidate()
                self.animTimer = nil
                self.setDisplayOffset(target)
            }
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func cancelAnim() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

extension NoteCarouselView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView,
              let idx = textViews.firstIndex(of: tv) else { return }
        noteStore.updateContent(tv.string, at: idx)
    }
}
