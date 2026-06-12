import AppKit

final class PageIndicatorView: NSView {
    private var dots: [CALayer] = []
    private var current: Int = 0

    private let dotDiameter: CGFloat   = 5
    private let activeDiameter: CGFloat = 7
    private let spacing: CGFloat = 9

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

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

    private func layoutDots() {
        guard !dots.isEmpty else { return }
        let total = CGFloat(dots.count) * activeDiameter + CGFloat(dots.count - 1) * spacing
        var x = (bounds.width - total) / 2 + activeDiameter / 2
        let y = bounds.height / 2
        for d in dots {
            d.position = CGPoint(x: x, y: y)
            x += activeDiameter + spacing
        }
    }

    override func layout() {
        super.layout()
        layoutDots()
    }
}
