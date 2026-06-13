import AppKit

final class NoteCarouselView: NSView {
    var onCreateNote: (() -> Void)?
    var onPageChanged: ((Int) -> Void)?

    private let noteStore: NoteStore
    private var scrollViews: [NSScrollView] = []
    private var textViews: [NSTextView] = []

    private var container: NSView!
    private var ghostView: NSView!
    private var ghostLabel: NSTextField!
    private(set) var currentPage: Int = 0
    private var displayOffset: CGFloat = 0

    // MARK: - Drag state

    private enum Axis { case none, horizontal, vertical }
    private var gestureAxis  = Axis.none
    private var dragStart    = CGFloat(0)
    private var dragPage     = 0
    private var recentDeltas = [(t: CFTimeInterval, dx: CGFloat)]()

    // Raw overscroll: actual cumulative finger movement past the right edge.
    // Tracked independently from displayOffset (which is rubber-banded) so the
    // threshold is reachable — the rubber-banded ceiling is ~c, but rawOverscroll
    // can grow without bound.
    private var rawOverscroll: CGFloat = 0
    private var isOverThreshold = false
    private var pendingVelocity: CGFloat = 0

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
            let v = pendingVelocity
            pendingVelocity = 0
            springJump(to: newIdx, stiffness: 320, damping: 22, velocity: v)
            showToast("New Note")
        }
    }

    // Shared toast for create / delete — positioned just above the indicator strip.
    // Uses pure CATransaction throughout (no NSAnimationContext mixing) so the
    // first frame is always correct and there's no implicit-animation jank.
    private func showToast(_ text: String) {
        // Dismiss any in-progress toast immediately
        subviews
            .filter { $0.identifier == NSUserInterfaceItemIdentifier("toast") }
            .forEach { $0.removeFromSuperview() }

        let pill = NSView()
        pill.identifier  = NSUserInterfaceItemIdentifier("toast")
        pill.wantsLayer  = true
        pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        pill.layer?.cornerRadius    = 11
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font      = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        addSubview(pill)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor,      constant:  5),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor,  constant:  11),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -11),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Float just above the indicator strip
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        // Set initial state with actions disabled so no implicit animation fires
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.layer?.opacity   = 0
        pill.layer?.transform = CATransform3DMakeScale(0.90, 0.90, 1)
        CATransaction.commit()

        // Grow + fade in
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.20)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        pill.layer?.opacity   = 1
        pill.layer?.transform = CATransform3DIdentity
        CATransaction.commit()

        // Fade out after hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard pill.superview != nil else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
            CATransaction.setCompletionBlock { pill.removeFromSuperview() }
            pill.layer?.opacity   = 0
            pill.layer?.transform = CATransform3DMakeScale(0.90, 0.90, 1)
            CATransaction.commit()
        }
    }

    func deleteCurrentPage() {
        guard scrollViews.count > 1 else { return }
        stopAnim()

        let idx = currentPage
        let dying = scrollViews[idx]
        let w = bounds.width, h = bounds.height

        // Navigate to adjacent note (prefer previous; fall back to new index 0)
        let newPage = idx > 0 ? idx - 1 : 0
        currentPage = newPage

        scrollViews.remove(at: idx)
        textViews.remove(at: idx)

        // Relayout remaining pages at their new indices
        container.frame.size.width = w * CGFloat(scrollViews.count)
        for (i, sv) in scrollViews.enumerated() {
            sv.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        updateGhostFrame()

        // Fade the deleted note out while it's still in the container
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            dying.animator().alphaValue = 0
        } completionHandler: {
            dying.removeFromSuperview()
        }

        // Spring from where we are to the new target page, then focus immediately
        startSpring(to: CGFloat(newPage) * w, stiffness: 380, damping: 28)
        focusCurrent()
        showToast("Note Deleted")
    }

    func reorderPage(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex else { return }
        let sv = scrollViews.remove(at: fromIndex)
        let tv = textViews.remove(at: fromIndex)
        scrollViews.insert(sv, at: toIndex)
        textViews.insert(tv, at: toIndex)

        if currentPage == fromIndex {
            currentPage = toIndex
        } else if fromIndex < toIndex {
            if currentPage > fromIndex && currentPage <= toIndex { currentPage -= 1 }
        } else {
            if currentPage < fromIndex && currentPage >= toIndex { currentPage += 1 }
        }

        let w = bounds.width, h = bounds.height
        for (i, sv) in scrollViews.enumerated() {
            sv.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        displayOffset = CGFloat(currentPage) * w
        setOffset(displayOffset)
    }

    func navigateTo(_ page: Int) {
        guard page >= 0, page < scrollViews.count, page != currentPage else { return }
        springJump(to: page, stiffness: 420, damping: 30, velocity: 0)
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
        tv.isRichText           = true
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
        ghostLabel = label
        return v
    }

    var currentTextView: NSTextView? {
        guard currentPage < textViews.count else { return nil }
        return textViews[currentPage]
    }

    func focusCurrent() {
        guard let tv = currentTextView, let win = window, win.isVisible else { return }
        win.makeFirstResponder(tv)
    }

    // MARK: - Formatting

    func toggleBold() {
        guard let tv = currentTextView else { return }
        toggleTrait(.boldFontMask, in: tv)
    }

    func toggleUnderline() {
        guard let tv = currentTextView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let current = attrs[.underlineStyle] as? Int ?? 0
            attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            tv.typingAttributes = attrs
            return
        }
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range, options: []) { val, _, stop in
            if (val as? Int ?? 0) == 0 { allUnderlined = false; stop.pointee = true }
        }
        tv.shouldChangeText(in: range, replacementString: nil)
        storage.beginEditing()
        let style = allUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        storage.addAttribute(.underlineStyle, value: style, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    private func toggleTrait(_ trait: NSFontTraitMask, in tv: NSTextView) {
        let range = tv.selectedRange()
        let mgr   = NSFontManager.shared
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let font  = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 15)
            attrs[.font] = mgr.traits(of: font).contains(trait)
                ? mgr.convert(font, toNotHaveTrait: trait)
                : mgr.convert(font, toHaveTrait: trait)
            tv.typingAttributes = attrs
            return
        }
        guard let storage = tv.textStorage else { return }
        var allHas = true
        storage.enumerateAttribute(.font, in: range, options: []) { val, _, stop in
            let f = val as? NSFont ?? NSFont.systemFont(ofSize: 15)
            if !mgr.traits(of: f).contains(trait) { allHas = false; stop.pointee = true }
        }
        tv.shouldChangeText(in: range, replacementString: nil)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { val, sub, _ in
            let f    = val as? NSFont ?? NSFont.systemFont(ofSize: 15)
            let newF = allHas ? mgr.convert(f, toNotHaveTrait: trait)
                              : mgr.convert(f, toHaveTrait: trait)
            storage.addAttribute(.font, value: newF, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }

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

    // MARK: - Scroll interception

    func interceptScroll(_ event: NSEvent) -> NSEvent? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.phase == .began {
            gestureAxis  = .none
            dragStart    = displayOffset
            dragPage     = currentPage
            rawOverscroll = 0
            isOverThreshold = false
            recentDeltas.removeAll()
            stopAnim()
            ghostView.alphaValue = 0
        }

        if gestureAxis == .none {
            let adx = abs(dx), ady = abs(dy)
            if adx > 2 || ady > 2 {
                gestureAxis = (adx >= ady * 0.65) ? .horizontal : .vertical
            }
        }

        let isGesture  = !event.phase.isEmpty
        let isMomentum = !event.momentumPhase.isEmpty

        if gestureAxis == .vertical {
            if isGesture && (event.phase == .ended || event.phase == .cancelled) {
                gestureAxis = .none
            }
            return event
        }

        if gestureAxis == .none && !isGesture && !isMomentum { return event }

        if isGesture && event.phase == .changed {
            recentDeltas.append((CACurrentMediaTime(), dx))
            if recentDeltas.count > 8 { recentDeltas.removeFirst() }
        }

        if isGesture && event.phase == .changed {
            applyDelta(dx)
        }

        if isGesture && (event.phase == .ended || event.phase == .cancelled) {
            gestureAxis = .none
            settle()
        }

        return nil
    }

    // MARK: - Drag physics

    private func applyDelta(_ dx: CGFloat) {
        guard bounds.width > 0 else { return }
        let w = bounds.width
        let lastPage = max(0, scrollViews.count - 1)

        let softMin = CGFloat(max(0,        dragPage - 1)) * w
        let softMax = CGFloat(min(lastPage, dragPage + 1)) * w

        // Raw proposed offset — used for normal paging and to detect overscroll entry
        let proposed = displayOffset - dx

        if proposed < softMin {
            if dragPage == 0 {
                setOffset(softMin + rubberBand(proposed - softMin, band: w))
            } else {
                setOffset(softMin)
            }
            rawOverscroll = 0
            if ghostView.alphaValue > 0 { ghostView.alphaValue = 0 }

        } else if proposed > softMax && dragPage == lastPage {
            // Accumulate raw finger movement past the right edge independently
            // of the rubber-banded displayOffset so the threshold is always reachable.
            rawOverscroll += -dx   // dx < 0 when swiping left (toward new note)
            rawOverscroll = max(0, rawOverscroll)

            let threshold = w * 0.40
            let alpha = min(rawOverscroll / threshold, 1.0)
            ghostView.alphaValue = alpha

            let nowOver = rawOverscroll > threshold
            if nowOver != isOverThreshold {
                isOverThreshold = nowOver
                updateGhostForThreshold(nowOver)
            }

            // Visual rubber band is applied to rawOverscroll for the pull effect
            setOffset(softMax + stiffRubberBand(rawOverscroll, band: w))

        } else if proposed > softMax {
            setOffset(softMax)
            rawOverscroll = 0

        } else {
            setOffset(proposed)
            rawOverscroll = 0
            if ghostView.alphaValue > 0 { ghostView.alphaValue = 0 }
        }
    }

    private func updateGhostForThreshold(_ exceeded: Bool) {
        let borderColor = exceeded ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        ghostView.layer?.borderColor = borderColor
        CATransaction.commit()

        ghostLabel.stringValue = exceeded ? "Release to Create" : "+ New Note"
        ghostLabel.textColor   = exceeded ? .controlAccentColor : .tertiaryLabelColor
    }

    // Soft band for left-edge bounce
    private func rubberBand(_ x: CGFloat, band: CGFloat) -> CGFloat {
        let abs_x = abs(x)
        let c     = band * 0.55
        let y     = (1.0 - 1.0 / (abs_x / c + 1.0)) * c
        return x < 0 ? -y : y
    }

    // Stiffer band for new-note pull — provides resistance without a reachability ceiling
    // issue because rawOverscroll (not the visual offset) is used for the threshold check.
    private func stiffRubberBand(_ x: CGFloat, band: CGFloat) -> CGFloat {
        let c = band * 0.38
        let y = (1.0 - 1.0 / (x / c + 1.0)) * c
        return y
    }

    // MARK: - Settle

    private func settle() {
        let w = bounds.width
        guard w > 0 else { return }

        let vel = estimatedVelocity()

        if ghostView.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.ghostView.animator().alphaValue = 0
            }
        }

        if isOverThreshold {
            isOverThreshold = false
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            ghostView.layer?.borderColor = NSColor.separatorColor.cgColor
            CATransaction.commit()
            ghostLabel.stringValue = "+ New Note"
            ghostLabel.textColor   = .tertiaryLabelColor
        }

        if rawOverscroll > w * 0.40 {
            rawOverscroll = 0
            pendingVelocity = vel
            onCreateNote?()
            return
        }

        rawOverscroll = 0

        let delta = displayOffset - dragStart
        let posThreshold: CGFloat = w * 0.20
        let velThreshold: CGFloat = 250

        var target = currentPage

        if delta < -posThreshold || vel < -velThreshold {
            target = max(0, currentPage - 1)
        } else if delta > posThreshold || vel > velThreshold {
            target = min(scrollViews.count - 1, currentPage + 1)
        }

        springJump(to: target, stiffness: 420, damping: 30, velocity: vel)
    }

    private func estimatedVelocity() -> CGFloat {
        guard recentDeltas.count >= 2 else { return 0 }
        let recent = Array(recentDeltas.suffix(5))
        let totalDx = recent.map(\.dx).reduce(0, +)
        let dt = recent.last!.t - recent.first!.t
        guard dt > 0.001 else { return 0 }
        return -totalDx / dt
    }

    // MARK: - Spring animation

    private func springJump(to page: Int, stiffness: CGFloat, damping: CGFloat, velocity: CGFloat = 0) {
        let target = max(0, min(scrollViews.count - 1, page))

        if target != currentPage {
            currentPage = target
            onPageChanged?(target)
        }

        let targetOffset = CGFloat(target) * bounds.width
        startSpring(to: targetOffset, stiffness: stiffness, damping: damping, initialVelocity: velocity)

        // Focus immediately — makeFirstResponder works regardless of animation state
        focusCurrent()
    }

    private func startSpring(to targetOff: CGFloat, stiffness: CGFloat, damping: CGFloat, initialVelocity: CGFloat = 0) {
        stopAnim()
        springPos    = displayOffset
        springVel    = initialVelocity
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
