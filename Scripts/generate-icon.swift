#!/usr/bin/env swift
// Generates Typee.icns — warm cream background with a soft "T" lettermark.
// Usage: swift Scripts/generate-icon.swift

import AppKit
import CoreGraphics

func makeIcon(size: Int) -> NSImage {
    let sz = CGFloat(size)
    let img = NSImage(size: NSSize(width: sz, height: sz))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    // Background: warm cream rounded rect
    let cream = NSColor(red: 0.98, green: 0.97, blue: 0.91, alpha: 1)
    let accent = NSColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1) // warm brown

    let corner = sz * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: sz, height: sz),
                        cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.setFillColor(cream.cgColor)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Subtle inner shadow / border
    ctx.setStrokeColor(NSColor(red: 0.88, green: 0.84, blue: 0.74, alpha: 1).cgColor)
    ctx.setLineWidth(sz * 0.015)
    ctx.addPath(bgPath)
    ctx.strokePath()

    // "T" lettermark
    let font = CTFontCreateWithName("Georgia-Bold" as CFString, sz * 0.56, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: accent,
    ]
    let attrStr = NSAttributedString(string: "T", attributes: attrs)
    let line = CTLineCreateWithAttributedString(attrStr)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    let tx = (sz - bounds.width) / 2 - bounds.minX
    let ty = (sz - bounds.height) / 2 - bounds.minY + sz * 0.02
    ctx.textPosition = CGPoint(x: tx, y: ty)
    CTLineDraw(line, ctx)

    img.unlockFocus()
    return img
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetDir = "Typee.iconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for sz in sizes {
    let img = makeIcon(size: sz)
    guard let tiff = img.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff),
          let png  = bmp.representation(using: .png, properties: [:]) else { continue }

    let name1x = "\(iconsetDir)/icon_\(sz)x\(sz).png"
    try? png.write(to: URL(fileURLWithPath: name1x))

    if sz <= 512 {
        let img2x = makeIcon(size: sz * 2)
        guard let t2 = img2x.tiffRepresentation,
              let b2 = NSBitmapImageRep(data: t2),
              let p2 = b2.representation(using: .png, properties: [:]) else { continue }
        let name2x = "\(iconsetDir)/icon_\(sz)x\(sz)@2x.png"
        try? p2.write(to: URL(fileURLWithPath: name2x))
    }
    print("  \(sz)x\(sz)")
}

print("✓ Iconset written to \(iconsetDir)/")
