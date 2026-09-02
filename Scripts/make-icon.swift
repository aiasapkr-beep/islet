// Renders Resources/AppIcon.icns: a dark rounded tile with a notch and two usage rings.
// Run: swift Scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    // Tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill(); tile.fill()
    // Screen glow area
    let screen = NSBezierPath(roundedRect: NSRect(x: s * 0.10, y: s * 0.14, width: s * 0.80, height: s * 0.66), xRadius: s * 0.07, yRadius: s * 0.07)
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1).setFill(); screen.fill()
    // Notch
    let notch = NSBezierPath(roundedRect: NSRect(x: s * 0.36, y: s * 0.71, width: s * 0.28, height: s * 0.12), xRadius: s * 0.04, yRadius: s * 0.04)
    NSColor.black.setFill(); notch.fill()
    // Rings
    func ring(cx: CGFloat, cy: CGFloat, r: CGFloat, fraction: CGFloat, color: NSColor) {
        let track = NSBezierPath(); track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = s * 0.055; NSColor.white.withAlphaComponent(0.15).setStroke(); track.stroke()
        let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = s * 0.055; arc.lineCapStyle = .round; color.setStroke(); arc.stroke()
    }
    ring(cx: s * 0.34, cy: s * 0.44, r: s * 0.13, fraction: 0.42, color: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1))
    ring(cx: s * 0.66, cy: s * 0.44, r: s * 0.13, fraction: 0.71, color: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1))
    img.unlockFocus()
    return img
}

let fm = FileManager.default
let outDir = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let img = render(size: px)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
let p = Process(); p.launchPath = "/usr/bin/iconutil"; p.arguments = ["-c", "icns", outDir, "-o", "Resources/AppIcon.icns"]
p.launch(); p.waitUntilExit()
try? fm.removeItem(atPath: outDir)
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
