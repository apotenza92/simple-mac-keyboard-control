import Foundation
import CoreGraphics

// Expand strokes before Icon Composer sees them: no zero-width gradient bounds,
// stroke-cap seams, or overlapping speaker fill/stroke surfaces.
func outlined(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}
func svg(_ path: CGPath) -> String {
    var result = ""
    func point(_ p: CGPoint) -> String { String(format: "%.6f %.6f", Double(p.x), Double(p.y)) }
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: result += "M" + point(e.points[0])
        case .addLineToPoint: result += "L" + point(e.points[0])
        case .addQuadCurveToPoint: result += "Q" + point(e.points[0]) + " " + point(e.points[1])
        case .addCurveToPoint: result += "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2])
        case .closeSubpath: result += "Z"
        @unknown default: fatalError("Unknown path element")
        }
    }
    return result
}
let sun = CGMutablePath()
sun.move(to: CGPoint(x:9,y:5.25))
sun.addCurve(to: CGPoint(x:5.25,y:9), control1: CGPoint(x:6.928932,y:5.25), control2: CGPoint(x:5.25,y:6.928932))
sun.addCurve(to: CGPoint(x:9,y:12.75), control1: CGPoint(x:5.25,y:11.071068), control2: CGPoint(x:6.928932,y:12.75))
for (a,b,c,d): (CGFloat,CGFloat,CGFloat,CGFloat) in [(9,1.5,9,3),(3.7,3.7,4.8,4.8),(1.5,9,3,9),(3.7,14.3,4.8,13.2),(9,15,9,16.5)] {
    sun.move(to: CGPoint(x:a,y:b)); sun.addLine(to: CGPoint(x:c,y:d))
}
let wave = CGMutablePath()
wave.move(to: CGPoint(x:14.7,y:6.3))
wave.addCurve(to: CGPoint(x:14.7,y:11.7), control1: CGPoint(x:17.1,y:7.7), control2: CGPoint(x:17.1,y:10.3))
let speaker = CGMutablePath()
speaker.move(to: CGPoint(x:8.2,y:7.35))
for (x,y): (CGFloat,CGFloat) in [(9.85,7.35),(13.2,4.4),(13.2,13.6),(9.85,10.65),(8.2,10.65)] { speaker.addLine(to: CGPoint(x:x,y:y)) }
speaker.closeSubpath()
let expandedSpeaker = speaker.union(outlined(speaker, width:0.5))
let data = try JSONSerialization.data(withJSONObject: ["sun":svg(outlined(sun,width:1.3)),"wave":svg(outlined(wave,width:1.3)),"speaker":svg(expandedSpeaker)], options:[.prettyPrinted,.sortedKeys])
try data.write(to: URL(fileURLWithPath:CommandLine.arguments[1]))
