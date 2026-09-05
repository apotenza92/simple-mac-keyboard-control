import AppKit
import CoreGraphics

/// A process-owned shade: quitting or crashing removes it without changing
/// display gamma tables, color profiles, or the monitor's backlight.
@MainActor
final class SoftwareBrightness {
    private var panels: [CGDirectDisplayID: NSPanel] = [:]

    var displayIDs: [CGDirectDisplayID] { Array(panels.keys).sorted() }

    func configure(levels: [CGDirectDisplayID: Int]) {
        remove()
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  CGDisplayIsBuiltin(id) == 0, levels[id] != nil else { continue }
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "KeyControl Software Brightness"
            panel.backgroundColor = .black
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            // Cover application content while keeping menu controls and the HUD usable.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panels[id] = panel
        }
        for (id, percent) in levels { set(percent, for: id) }
    }

    func set(_ percent: Int, for id: CGDirectDisplayID) {
        if let panel = panels[id] {
            // Keep a visible floor so a held key cannot make the display black.
            panel.alphaValue = 0.9 * (1 - Double(Level.clamp(percent)) / 100)
            if percent >= 100 {
                if panel.isVisible { panel.orderOut(nil) }
            } else if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    func remove() {
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }
}
