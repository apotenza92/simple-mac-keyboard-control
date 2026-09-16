// Read-only topology trace for bounded display-switching experiments.
// Usage: swift scripts/trace-display-layout.swift [seconds]
import CoreGraphics
import Foundation

let duration = min(120, max(1, Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15))
let started = ProcessInfo.processInfo.systemUptime
var previous = Data()
repeat {
    var ids = [CGDirectDisplayID](repeating: 0, count: 64)
    var count: UInt32 = 0
    let error = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    guard error == .success else { fatalError("Display enumeration failed: \(error)") }
    let displays: [[String: Any]] = ids.prefix(Int(count)).map { id in
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        return ["id": id, "main": CGDisplayIsMain(id) != 0,
                "active": CGDisplayIsActive(id) != 0,
                "x": bounds.origin.x, "y": bounds.origin.y,
                "width": bounds.width, "height": bounds.height,
                "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                "rotation": CGDisplayRotation(id)]
    }
    let state = try JSONSerialization.data(withJSONObject: displays, options: [.sortedKeys])
    if state != previous {
        let record: [String: Any] = ["elapsed": ProcessInfo.processInfo.systemUptime - started,
                                     "mainID": CGMainDisplayID(), "displays": displays]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        fflush(stdout)
        previous = state
    }
    Thread.sleep(forTimeInterval: 0.1)
} while ProcessInfo.processInfo.systemUptime - started < duration
