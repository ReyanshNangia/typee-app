import AppKit

// MARK: - Palette definition

struct NoteColor {
    let name: String
    let swatch: NSColor
    let background: NSColor

    static let palette: [NoteColor] = [
        NoteColor("cream",    r: 1.00, g: 0.97, b: 0.91),
        NoteColor("rose",     r: 1.00, g: 0.87, b: 0.90),
        NoteColor("sage",     r: 0.86, g: 0.95, b: 0.86),
        NoteColor("sky",      r: 0.84, g: 0.93, b: 1.00),
        NoteColor("lavender", r: 0.91, g: 0.87, b: 0.97),
        NoteColor("peach",    r: 1.00, g: 0.93, b: 0.84),
    ]

    init(_ name: String, r: CGFloat, g: CGFloat, b: CGFloat) {
        self.name       = name
        self.swatch     = NSColor(red: r, green: g, blue: b, alpha: 1.0)
        self.background = NSColor(red: r, green: g, blue: b, alpha: 0.50)
    }

    static func background(named name: String?) -> NSColor? {
        guard let n = name else { return nil }
        return palette.first { $0.name == n }?.background
    }
}

// MARK: - ColorPickerView

final class ColorPickerView: NSView {
    var onColorSelected: ((String?) -> Void)?
    private(set) var selectedName: String?

    private let diameter: CGFloat
    private let gap: CGFloat

    // "none" (clear) + all palette entries
    private var allNames: [String?] { [nil] + NoteColor.palette.map { $0.name } }
    private var layers: [CALayer] = []

    var preferredWidth: CGFloat {
        let n = CGFloat(allNames.count)
        return n * diameter + (n - 1) * gap
    }

    // MARK: - Init

    init(diameter: CGFloat = 11, gap: CGFloat = 6) {
        self.diameter = diameter
        self.gap      = gap
        super.init(frame: .zero)
        wantsLayer = true
        buildLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildLayers() {
        for (i, name) in allNames.enumerated() {
            let l = CALayer()
            l.bounds        = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            l.cornerRadius  = diameter / 2
            l.masksToBounds = true

            if let n = name, let nc = NoteColor.palette.first(where: { $0.name == n }) {
                l.backgroundColor = nc.swatch.cgColor
            } else {
                // "no color" swatch
                l.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
                l.borderColor     = NSColor.tertiaryLabelColor.withAlphaComponent(0.6).cgColor
                l.borderWidth     = 1.0
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.addSublayer(l)
            CATransaction.commit()
            layers.append(l)

            _ = i // suppress warning
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let cy = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, l) in layers.enumerated() {
            l.position = CGPoint(x: CGFloat(i) * (diameter + gap) + diameter / 2, y: cy)
        }
        CATransaction.commit()
        applyStyles(animated: false)
    }

    // MARK: - Selection

    func select(_ name: String?) {
        selectedName = name
        applyStyles(animated: true)
    }

    private func applyStyles(animated: Bool) {
        let work = {
            for (i, name) in self.allNames.enumerated() {
                let l = self.layers[i]
                let sel = (name == self.selectedName)
                l.transform  = sel ? CATransform3DMakeScale(1.25, 1.25, 1) : CATransform3DIdentity
                if name == nil {
                    l.borderWidth = sel ? 2.0 : 1.0
                    l.borderColor = sel
                        ? NSColor.controlAccentColor.cgColor
                        : NSColor.tertiaryLabelColor.withAlphaComponent(0.6).cgColor
                } else {
                    l.borderWidth = sel ? 2.0 : 0.0
                    l.borderColor = NSColor.controlAccentColor.cgColor
                }
            }
        }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            work()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            work()
            CATransaction.commit()
        }
    }

    // MARK: - Hit testing

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let cy = bounds.height / 2
        for (i, name) in allNames.enumerated() {
            let cx = CGFloat(i) * (diameter + gap) + diameter / 2
            if hypot(pt.x - cx, pt.y - cy) <= diameter {
                if name == selectedName {
                    selectedName = nil
                    onColorSelected?(nil)
                } else {
                    selectedName = name
                    onColorSelected?(name)
                }
                applyStyles(animated: true)
                return
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}
