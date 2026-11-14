// Draws the app icon and writes AppIcon.iconset; build with: tools/make-icon.sh
import AppKit

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // macOS icon grid: rounded square inset about 10% with a soft shadow.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor.black.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1), NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)])!.draw(in: shape, angle: -90)
    // Half-lit disc: the menu bar glyph.
    let center = NSPoint(x: s / 2, y: s / 2), radius = s * 0.23
    let lit = NSBezierPath()
    lit.move(to: NSPoint(x: center.x, y: center.y - radius))
    lit.appendArc(withCenter: center, radius: radius, startAngle: 270, endAngle: 90, clockwise: true)
    lit.close()
    NSColor(red: 0.45, green: 0.90, blue: 0.55, alpha: 1).setFill(); lit.fill()
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = s * 0.03
    NSColor.white.withAlphaComponent(0.95).setStroke(); ring.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(points * scale).write(to: out.appendingPathComponent(name))
}
