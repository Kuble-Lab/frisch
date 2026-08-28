import AppKit

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
    let path = NSBezierPath(roundedRect: inset, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.42, alpha: 1),
                              ending: NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.26, alpha: 1))!
    gradient.draw(in: path, angle: -90)
    let str = "🍃" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.55)]
    let sz = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2), withAttributes: attrs)
    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, _ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

for base in [16, 32, 128, 256, 512] {
    savePNG(render(base), base, "icon_\(base)x\(base)")
    savePNG(render(base * 2), base * 2, "icon_\(base)x\(base)@2x")
}
print("iconset done")
