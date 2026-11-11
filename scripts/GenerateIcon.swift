import AppKit

let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
    NSColor(red: 0.07, green: 0.115, blue: 0.08, alpha: 1).setFill()
    let background = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
    background.fill()
    background.addClip()
    for index in 0..<8 {
        let radius = CGFloat(150 + index * 61)
        NSColor(red: 0.765, green: 0.957, blue: 0.478, alpha: CGFloat(0.15 - Double(index) * 0.012)).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 710 - radius, y: 310 - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = 3
        ring.stroke()
    }
    let heights: [CGFloat] = [170, 330, 470, 290, 170]
    NSColor(red: 0.765, green: 0.957, blue: 0.478, alpha: 1).setFill()
    for (index, height) in heights.enumerated() {
        let bar = NSRect(x: 286 + CGFloat(index) * 94, y: 512 - height / 2, width: 55, height: height)
        NSBezierPath(roundedRect: bar, xRadius: 27.5, yRadius: 27.5).fill()
    }
    NSColor(white: 1, alpha: 0.13).setStroke()
    let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 194, yRadius: 194)
    edge.lineWidth = 3
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let url = URL(fileURLWithPath: folder).appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
