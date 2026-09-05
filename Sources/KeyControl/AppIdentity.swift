import AppKit

/// Public names follow the signed bundle; compatibility identifiers stay fixed.
enum AppIdentity {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Simple Mac Keyboard Control"
    }

    /// Matches the square half-sun/speaker SVG. macOS supplies template tinting.
    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let sun = NSBezierPath()
            // Two cubic quarter-circles form the left half of the sun.
            sun.move(to: NSPoint(x: 9, y: 5.25))
            sun.curve(to: NSPoint(x: 5.25, y: 9),
                      controlPoint1: NSPoint(x: 6.929, y: 5.25),
                      controlPoint2: NSPoint(x: 5.25, y: 6.929))
            sun.curve(to: NSPoint(x: 9, y: 12.75),
                      controlPoint1: NSPoint(x: 5.25, y: 11.071),
                      controlPoint2: NSPoint(x: 6.929, y: 12.75))
            sun.lineWidth = 1.3
            sun.lineCapStyle = .round
            sun.stroke()
            let rays = NSBezierPath()
            for (x1, y1, x2, y2): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                (9, 1.5, 9, 3), (3.7, 3.7, 4.8, 4.8), (1.5, 9, 3, 9),
                (3.7, 14.3, 4.8, 13.2), (9, 15, 9, 16.5)
            ] {
                rays.move(to: NSPoint(x: x1, y: y1))
                rays.line(to: NSPoint(x: x2, y: y2))
            }
            rays.lineWidth = 1.3
            rays.lineCapStyle = .round
            rays.stroke()
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 14.7, y: 6.3))
            wave.curve(to: NSPoint(x: 14.7, y: 11.7),
                       controlPoint1: NSPoint(x: 17.1, y: 7.7),
                       controlPoint2: NSPoint(x: 17.1, y: 10.3))
            wave.lineWidth = 1.3
            wave.lineCapStyle = .round
            wave.stroke()
            let speaker = NSBezierPath()
            speaker.move(to: NSPoint(x: 8.2, y: 7.35))
            for (x, y): (CGFloat, CGFloat) in [(9.85, 7.35), (13.2, 4.4), (13.2, 13.6), (9.85, 10.65), (8.2, 10.65)] {
                speaker.line(to: NSPoint(x: x, y: y))
            }
            speaker.close()
            speaker.fill()
            speaker.lineWidth = 0.5
            speaker.lineJoinStyle = .round
            speaker.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
