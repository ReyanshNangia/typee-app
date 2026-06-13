import AppKit

final class PageIndicatorView: NSView {
    var onPageSelected: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?

    private var dots: [CALayer] = []
    private var current: Int = 0

    private let dotDiameter: CGFloat    = 5
    private let activeDiameter: CGFloat = 7
    private let spacing: CGFloat        = 9
    private let hitRadius: CGFloat      = 14   // generous touch target

    // Drag state
    private var dragIndex: Int      = -1
    private var dragStartMouseX: CGFloat = 0
    private var dragCurrentX: CGFloat   = 0
    private var isDragging: Bool    = false
    private var lastTargetIndex: Int = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func reload(count: Int, current: Int) {
        self.current = max(0, min(count - 1, current))
        rebuild(count: count)
    }

    func moveTo(_ page: Int) {
        guard page >= 0, page < dots.count, page != current else { return }
        let old = current
        current = page
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        styleDot(dots[old],  active: false)
        styleDot(dots[page], active: true)
        CATransaction.commit()
    }

    // MARK: - Build

    private func rebuild(count: Int) {
        dots.forEach { $0.removeFromSuperlayer() }
        dots.removeAll()
        guard count > 0 else { return }
        for i in 0..<count {
            let d = CALayer()
            d.cornerRadius = activeDiameter / 2
            d.bounds = CGRect(x: 0, y: 0, width: activeDiameter, height: activeDiameter)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            styleDot(d, active: i == current)
            CATransaction.commit()
            layer?.addSublayer(d)
            dots.append(d)
        }
        layoutDots()
    }

    private func styleDot(_ d: CALayer, active: Bool) {
        let s = active ? 1.0 : (dotDiameter / activeDiameter)
        d.transform = CATransform3DMakeScale(s, s, 1)
        d.backgroundColor = active
            ? NSColor.labelColor.withAlphaComponent(0.55).cgColor
            : NSColor.labelColor.withAlphaComponent(0.18).cgColor
    }

    // MARK: - Layout

    private func slotPositions() -> [CGFloat] {
        guard !dots.isEmpty else { return [] }
        let total = CGFloat(dots.count) * activeDiameter + CGFloat(dots.count - 1) * spacing
        var x = (bounds.width - total) / 2 + activeDiameter / 2
        var result: [CGFloat] = []
        for _ in dots {
            result.append(x)
            x += activeDiameter + spacing
        }
        return result
    }

    private func layoutDots() {
        guard !dots.isEmpty else { return }
        let slots = slotPositions()
        let y = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, d) in dots.enumerated() {
            d.position = CGPoint(x: slots[i], y: y)
        }
        CATransaction.commit()
    }

    private func layoutDotsAnimated(duration: CFTimeInterval = 0.2) {
        guard !dots.isEmpty else { return }
        let slots = slotPositions()
        let y = bounds.height / 2
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        for (i, d) in dots.enumerated() {
            d.position = CGPoint(x: slots[i], y: y)
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if !isDragging { layoutDots() }
    }

    // MARK: - Hit testing

    private func dotIndex(at point: NSPoint) -> Int? {
        let slots = slotPositions()
        let y = bounds.height / 2
        for (i, x) in slots.enumerated() {
            if abs(point.x - x) <= hitRadius && abs(point.y - y) <= hitRadius {
                return i
            }
        }
        return nil
    }

    private func targetIndex(forX x: CGFloat) -> Int {
        let slots = slotPositions()
        guard !slots.isEmpty else { return 0 }
        var best = 0
        var bestDist = abs(x - slots[0])
        for i in 1..<slots.count {
            let d = abs(x - slots[i])
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let idx = dotIndex(at: pt) else { return }
        dragIndex      = idx
        dragStartMouseX = pt.x
        dragCurrentX   = slotPositions()[idx]
        isDragging     = false
        lastTargetIndex = idx
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragIndex >= 0 else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let deltaFromStart = pt.x - dragStartMouseX
        if !isDragging && abs(deltaFromStart) < 4 { return }
        isDragging = true

        let slots = slotPositions()
        let y = bounds.height / 2

        // Clamp dragged dot to the slot range
        let minX = slots.first ?? 0
        let maxX = slots.last  ?? 0
        dragCurrentX = max(minX, min(maxX, slots[dragIndex] + deltaFromStart))

        let target = targetIndex(forX: dragCurrentX)

        // Move dragged dot directly (no animation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dots[dragIndex].position.x = dragCurrentX
        CATransaction.commit()

        // Animate other dots into their shifted positions
        if target != lastTargetIndex {
            lastTargetIndex = target
            var virtualOrder = Array(0..<dots.count)
            virtualOrder.remove(at: dragIndex)
            let insertAt = min(target, virtualOrder.count)
            virtualOrder.insert(dragIndex, at: insertAt)

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            for (slotIdx, dotIdx) in virtualOrder.enumerated() where dotIdx != dragIndex {
                dots[dotIdx].position = CGPoint(x: slots[slotIdx], y: y)
            }
            CATransaction.commit()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragIndex >= 0 else { return }
        let fromIndex = dragIndex
        dragIndex = -1

        if isDragging {
            isDragging = false
            let toIndex = lastTargetIndex
            if toIndex != fromIndex {
                // Update current before notifying so reload gets the right index
                if current == fromIndex { current = toIndex }
                else if fromIndex < toIndex {
                    if current > fromIndex && current <= toIndex { current -= 1 }
                } else {
                    if current < fromIndex && current >= toIndex { current += 1 }
                }
                onReorder?(fromIndex, toIndex)
                // Caller will reload; snap dots back cleanly
            } else {
                layoutDotsAnimated()
            }
        } else {
            // Pure click — navigate to that note
            onPageSelected?(fromIndex)
        }
    }

    // Ensure the view receives mouse events even on transparent background
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Prevent the window-drag system from stealing mouseDown on this view
    override var mouseDownCanMoveWindow: Bool { false }
}
