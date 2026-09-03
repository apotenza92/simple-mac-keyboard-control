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
                .accessibilityLabel("KeyControl")
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
                Text("KeyControl")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(statusText)
            }

            controlSection(
                title: audio.level.isMuted ? "Muted" : "Volume",
                symbol: audio.level.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                value: Binding(
                    get: { Double(audio.level.percent) },
                    set: { audio.setVolume(Int($0.rounded())) }
                ),
                trailing: "\(audio.level.percent)%"
            )
            .opacity(audio.isEnabled ? 1 : 0.45)

            if brightness.isAvailable {
                controlSection(
                    title: "Brightness",
                    symbol: "sun.max.fill",
                    value: Binding(
                        get: { Double(brightness.percent) },
                        set: { brightness.set(Int($0.rounded())) }
                    ),
                    trailing: "\(brightness.percent)%"
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

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

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
        symbol: String,
        value: Binding<Double>,
        trailing: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(trailing).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
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
