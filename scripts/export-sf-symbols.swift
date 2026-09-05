import AppKit

// Render genuine SF Symbols at high resolution. The icon's keycap geometry stays
// editable SVG; these native glyphs are embedded PNGs, not hand-drawn imitations.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for name in ["sun.min", "sun.max", "speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.3.fill"] {
    for (suffix, tint) in [("", NSColor.black), ("-white", NSColor.white)] {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 256, weight: .regular)
                .applying(.init(paletteColors: [tint]))) else { fatalError("Missing SF Symbol: \(name)") }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = min(448 / symbol.size.width, 448 / symbol.size.height)
        let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: NSRect(x: (512-size.width)/2, y: (512-size.height)/2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + suffix + ".png"))
    }
}
