// Draws Resources/AppIcon.icns: a tidal channel (a Priel) winding through sand flats.
//   swift Scripts/icon.swift
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // The macOS icon grid: an 824/1024 rounded square, centred.
    let inset = s * 100 / 1024
    let box = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.95, green: 0.89, blue: 0.76, alpha: 1),
                        NSColor(srgbRed: 0.84, green: 0.74, blue: 0.56, alpha: 1)])!.draw(in: box, angle: -90)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: box.minX + x * box.width, y: box.minY + y * box.height) }
    let channel = NSBezierPath()
    channel.move(to: p(-0.1, 0.18))
    channel.curve(to: p(0.48, 0.42), controlPoint1: p(0.2, 0.08), controlPoint2: p(0.25, 0.5))
    channel.curve(to: p(1.1, 0.86), controlPoint1: p(0.72, 0.34), controlPoint2: p(0.8, 0.95))
    channel.lineCapStyle = .round
    for (width, color) in [(0.25, NSColor(srgbRed: 0.76, green: 0.65, blue: 0.47, alpha: 1)),
                           (0.19, NSColor(srgbRed: 0.10, green: 0.42, blue: 0.62, alpha: 1)),
                           (0.07, NSColor(srgbRed: 0.33, green: 0.67, blue: 0.84, alpha: 1))] {
        channel.lineWidth = box.width * width
        color.setStroke()
        channel.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: set.appending(path: "icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: set.appending(path: "icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try! draw(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
