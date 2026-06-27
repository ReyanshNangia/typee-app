#!/usr/bin/env swift
// Renders the DMG background — warm cream with a soft "drag to install" hint.
// Output: Scripts/dmg-background.png (and @2x). Usage: swift Scripts/generate-dmg-background.swift

import AppKit

// Logical DMG window content size (points). The Finder window is set to match.
let W: CGFloat = 620
let H: CGFloat = 420

func render(scale: CGFloat) -> Data? {
    let pxW = Int(W * scale), pxH = Int(H * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: W, height: H)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // Vertical cream gradient background
    let top = NSColor(red: 0.99, green: 0.98, blue: 0.93, alpha: 1)
    let bot = NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
    let grad = NSGradient(starting: top, ending: bot)!
    grad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    let brown = NSColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1)
    let faint = NSColor(red: 0.62, green: 0.50, blue: 0.38, alpha: 1)

    // Title
    let title = "Install Typee"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Georgia-Bold", size: 30) ?? NSFont.boldSystemFont(ofSize: 30),
        .foregroundColor: brown,
    ]
    let tSize = title.size(withAttributes: titleAttrs)
    title.draw(at: NSPoint(x: (W - tSize.width) / 2, y: H - 70), withAttributes: titleAttrs)

    // Subtitle
    let sub = "Drag the app onto the Applications folder"
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: faint,
    ]
    let sSize = sub.size(withAttributes: subAttrs)
    sub.draw(at: NSPoint(x: (W - sSize.width) / 2, y: H - 96), withAttributes: subAttrs)

    // Arrow between the two icon slots (icons themselves are placed by Finder).
    // App icon sits ~x=165, Applications ~x=455, vertically centered around y=185.
    let arrowY: CGFloat = 195
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 250, y: arrowY))
    path.line(to: NSPoint(x: 370, y: arrowY))
    faint.withAlphaComponent(0.55).setStroke()
    path.lineWidth = 4
    path.lineCapStyle = .round
    path.stroke()
    // Arrowhead
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 370, y: arrowY))
    head.line(to: NSPoint(x: 354, y: arrowY + 10))
    head.move(to: NSPoint(x: 370, y: arrowY))
    head.line(to: NSPoint(x: 354, y: arrowY - 10))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

if let d1 = render(scale: 1) {
    try? d1.write(to: URL(fileURLWithPath: "Scripts/dmg-background.png"))
}
if let d2 = render(scale: 2) {
    try? d2.write(to: URL(fileURLWithPath: "Scripts/dmg-background@2x.png"))
}
print("✓ DMG background written to Scripts/dmg-background.png")
