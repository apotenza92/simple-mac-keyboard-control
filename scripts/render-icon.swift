import AppKit

// Reproducible vector artwork rendered at each macOS icon resolution.
// No external image assets, fonts, or graphics packages are needed.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func symbol(_ name: String, rect: NSRect, tint: NSColor) {
    let configuration = NSImage.SymbolConfiguration(pointSize: 180, weight: .medium)
        .applying(.init(paletteColors: [tint]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { fatalError("Missing symbol: \(name)") }
    let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
    let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
    image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                         width: size.width, height: size.height))
}

func render(pixels: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    rounded(NSRect(x: 100, y: 86, width: 824, height: 824), radius: 184, fill: color(19, 22, 27))
    rounded(NSRect(x: 100, y: 106, width: 824, height: 824), radius: 184, fill: color(39, 43, 50))
    rounded(NSRect(x: 164, y: 290, width: 330, height: 420), radius: 68, fill: color(17, 20, 25))
    rounded(NSRect(x: 530, y: 290, width: 330, height: 420), radius: 68, fill: color(17, 20, 25))
    rounded(NSRect(x: 164, y: 322, width: 330, height: 420), radius: 68, fill: color(244, 181, 68))
    rounded(NSRect(x: 530, y: 322, width: 330, height: 420), radius: 68, fill: color(242, 240, 235))
    symbol("sun.max.fill", rect: NSRect(x: 220, y: 423, width: 218, height: 218), tint: color(39, 43, 50))
    symbol("speaker.wave.2.fill", rect: NSRect(x: 584, y: 423, width: 222, height: 218), tint: color(39, 43, 50))

    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: output.appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
