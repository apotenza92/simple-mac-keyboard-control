import AppKit
import KeyControlCore
import SwiftUI

@main
struct KeyControlApp: App {
    @StateObject private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        DispatchQueue.main.async { model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            KeyControlMenu(model: model)
        } label: {
            Image(systemName: "keyboard.badge.ellipsis")
                .accessibilityLabel("Simple Mac Keyboard Control")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct KeyControlMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var audio: AudioController
    @ObservedObject private var brightness: DDCController
    @ObservedObject private var launchAtLogin: LaunchAtLoginController

    init(model: AppModel) {
        self.model = model
        audio = model.audio
        brightness = model.brightness
        launchAtLogin = model.launchAtLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Simple Mac Keyboard Control")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(statusText)
            }

            controlSection(
                title: audio.deviceName ?? "Audio Output",
                leadingSymbol: "speaker.fill",
                trailingSymbol: "speaker.wave.3.fill",
                value: Binding(
                    get: { Double(audio.level.percent) },
                    set: { audio.setVolume(Int($0.rounded())) }
                ),
                isMuted: audio.level.isMuted
            )
            .opacity(audio.isEnabled ? 1 : 0.45)

            if brightness.isAvailable {
                controlSection(
                    title: model.brightnessDeviceName,
                    leadingSymbol: "sun.min.fill",
                    trailingSymbol: "sun.max.fill",
                    value: Binding(
                        get: { Double(brightness.percent) },
                        set: { brightness.set(Int($0.rounded())) }
                    ),
                    isMuted: false
                )
                .opacity(brightness.isEnabled ? 1 : 0.45)
            }

            Divider()

            Toggle("Volume keys", isOn: $audio.isEnabled)
            Toggle("Brightness keys", isOn: $brightness.isEnabled)
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            if !model.hasAccessibilityPermission {
                permissionRow(
                    text: "Allow Accessibility for media keys",
                    action: model.requestAccessibility
                )
            }
            if brightness.isAvailable,
               !brightness.hasActiveBuiltInDisplay,
               !model.hasInputMonitoringPermission {
                permissionRow(
                    text: "Allow Input Monitoring for brightness keys",
                    action: model.requestInputMonitoring
                )
            }

            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Button("Privacy Settings") { model.openPrivacySettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { model.quit() }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 310)
    }

    private func controlSection(
        title: String,
        leadingSymbol: String,
        trailingSymbol: String,
        value: Binding<Double>,
        isMuted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MenuLevelMeter(
                value: value,
                isMuted: isMuted,
                leadingSymbol: leadingSymbol,
                trailingSymbol: trailingSymbol
            )
        }
    }

    private func permissionRow(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: "hand.raised.fill")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private var statusColor: Color {
        switch audio.state {
        case .active, .native: return .green
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var statusText: String {
        switch audio.state {
        case .active(let device):
            return "Keyboard volume is controlling \(device)."
        case .native(let device):
            return "\(device) already supports macOS volume."
        case .failed(let device, let reason):
            return [device, reason].compactMap { $0 }.joined(separator: ": ")
        case .stopped:
            return "Volume key control is off."
        }
    }
}

private struct MenuLevelMeter: View {
    @Binding var value: Double
    let isMuted: Bool
    let leadingSymbol: String
    let trailingSymbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12)
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.22))
                        Capsule()
                            .fill(.primary.opacity(0.82))
                            .frame(width: geometry.size.width * displayedFraction)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { gesture in
                            value = min(max(gesture.location.x / geometry.size.width * 100, 0), 100)
                        }
                    )
                }
                .frame(height: 4)
                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { index in
                        Circle().fill(.secondary.opacity(0.24)).frame(width: 2, height: 2)
                        if index != 15 { Spacer() }
                    }
                }
                .frame(height: 2)
            }
            Image(systemName: trailingSymbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14)
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMuted ? "Muted" : "Level")
        .accessibilityValue("\(Int(value.rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, 100)
            case .decrement: value = max(value - 1, 0)
            @unknown default: break
            }
        }
    }

    private var displayedFraction: CGFloat {
        isMuted ? 0 : CGFloat(value) / 100
    }
}
