import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class OSDPresenter {
    enum Kind: String {
        case volume
        case muted
        case brightness

        var leadingSymbol: String {
            switch self {
            case .brightness: return "sun.min.fill"
            case .volume, .muted: return "speaker.fill"
            }
        }

        var trailingSymbol: String {
            switch self {
            case .brightness: return "sun.max.fill"
            case .volume, .muted: return "speaker.wave.3.fill"
            }
        }
    }

    private let panel: NSPanel
    private var dismissal: DispatchWorkItem?
    private let diagnostics = UserDefaults.standard

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.backgroundColor = .clear
        panel.title = "Simple Mac Keyboard Control HUD"
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
    }

    func show(kind: Kind, name: String, percent: Int, displayID: CGDirectDisplayID? = nil) {
        let targetID = displayID ?? CGMainDisplayID()
        showSwiftUI(kind: kind, name: name, percent: min(max(percent, 0), 100), displayID: targetID)
    }

    private func showSwiftUI(kind: Kind, name: String, percent: Int, displayID: CGDirectDisplayID) {
        dismissal?.cancel()
        panel.contentView = NSHostingView(
            rootView: OSDView(kind: kind, name: name, percent: percent)
        )

        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == displayID
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        let menuBarHeight = max(0, frame.maxY - screen.visibleFrame.maxY)
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - 16,
            y: frame.maxY - menuBarHeight - panel.frame.height - 8
        ))

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        diagnostics.set(kind.rawValue, forKey: "runtimeHUDKind")
        diagnostics.set(name, forKey: "runtimeHUDName")
        diagnostics.set(percent, forKey: "runtimeHUDPercent")
        diagnostics.set(displayID, forKey: "runtimeHUDDisplayID")
        diagnostics.set(true, forKey: "runtimeHUDVisible")
        diagnostics.set(diagnostics.integer(forKey: "runtimeHUDCount") + 1, forKey: "runtimeHUDCount")
        diagnostics.synchronize()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.panel.orderOut(nil)
                    self?.diagnostics.set(false, forKey: "runtimeHUDVisible")
                    self?.diagnostics.synchronize()
                }
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }
}

private struct OSDView: View {
    let kind: OSDPresenter.Kind
    let name: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            OSDLevel(kind: kind, percent: percent)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(width: 292, height: 64, alignment: .topLeading)
        .osdGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(percent) percent")
    }
}

private struct OSDLevel: View {
    let kind: OSDPresenter.Kind
    let percent: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind.leadingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12)
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(.white.opacity(0.88))
                            .frame(width: geometry.size.width * displayedFraction)
                    }
                }
                .frame(height: 4)
                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { index in
                        Circle().fill(.white.opacity(0.12)).frame(width: 2, height: 2)
                        if index != 15 { Spacer() }
                    }
                }
                .frame(height: 2)
            }
            Image(systemName: kind.trailingSymbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14)
        }
        .frame(height: 13)
    }

    private var displayedFraction: CGFloat {
        kind == .muted ? 0 : CGFloat(percent) / 100
    }
}

private extension View {
    @ViewBuilder
    func osdGlass() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}
