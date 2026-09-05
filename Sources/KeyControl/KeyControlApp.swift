import AppKit
import KeyControlCore
import SwiftUI

@main
struct KeyControlApp: App {
    @StateObject private var model: AppModel
    @StateObject private var updates = UpdateManager()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        DispatchQueue.main.async {
            if UpdateTestSession.current == nil { model.start() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.stop() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            KeyControlMenu(model: model, updates: updates)
        } label: {
            Image(nsImage: AppIdentity.menuImage)
                .renderingMode(.template)
                .accessibilityLabel(AppIdentity.name)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct KeyControlMenu: View {
    @State private var permissionsExpanded = false
    @ObservedObject private var appearance = ControlAppearance.shared
    let model: AppModel
    @ObservedObject var updates: UpdateManager
    @ObservedObject private var launchAtLogin: LaunchAtLoginController

    init(model: AppModel, updates: UpdateManager) {
        self.model = model
        self.updates = updates
        launchAtLogin = model.launchAtLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppIdentity.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            AudioControls(audio: model.audio)

            Divider()

            BrightnessControls(brightness: model.brightness)

            Divider()

            HStack {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { model.quit() }
                    .keyboardShortcut("q")
            }

            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Check for Updates…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)

            Divider()

            DisclosureGroup(isExpanded: $permissionsExpanded) {
                PermissionsView(model: model)
                    .padding(.top, 8)
            } label: {
                Button {
                    permissionsExpanded.toggle()
                } label: {
                    Text("Permissions")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(permissionsExpanded ? "Expanded" : "Collapsed")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 324)
        .foregroundStyle(.primary.opacity(0.92))
        .controlMenuSurface()
        .environment(\.colorScheme, appearance.colorScheme)
    }

}

private struct AudioControls: View {
    @ObservedObject var audio: AudioController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Volume keys", isOn: $audio.isEnabled)
                .toggleStyle(.checkbox)

            if audio.isEnabled {
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
                .disabled(!audio.canAdjustVolume)
                .opacity(audio.canAdjustVolume ? 1 : 0.45)
            } else {
                disabledPlaceholder(leadingSymbol: "speaker.fill", trailingSymbol: "speaker.wave.3.fill", label: "Volume keys off")
            }
        }

    }
}

private struct BrightnessControls: View {
    @ObservedObject var brightness: DDCController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Brightness keys", isOn: $brightness.isEnabled)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 8)
                if brightness.displays.count > 1 {
                    Toggle("Link brightness", isOn: $brightness.isLinked)
                        .toggleStyle(.checkbox)
                        .disabled(!brightness.isEnabled)
                }
            }

            if brightness.isEnabled && !brightness.isLinked && brightness.displays.count > 1 {
                Text("Controls brightness on the display under your mouse cursor.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }

            if brightness.isEnabled {
                ForEach(brightness.displays) { display in
                    controlSection(
                        title: display.name,
                        leadingSymbol: "sun.min.fill",
                        trailingSymbol: "sun.max.fill",
                        value: Binding(
                            get: { Double(brightness.displays.first { $0.id == display.id }?.percent ?? display.percent) },
                            set: { brightness.set(Int($0.rounded()), for: display.id) }
                        ),
                        isMuted: false
                    )
                    .disabled(!display.canAdjust)
                    .opacity(display.canAdjust ? 1 : 0.45)
                }
            } else {
                disabledPlaceholder(leadingSymbol: "sun.min.fill", trailingSymbol: "sun.max.fill", label: "Brightness keys off")
            }
        }

    }
}

private func disabledPlaceholder(leadingSymbol: String, trailingSymbol: String, label: String) -> some View {
    MenuLevelMeter(
        title: label,
        value: .constant(0),
        isMuted: false,
        leadingSymbol: leadingSymbol,
        trailingSymbol: trailingSymbol
    )
    .disabled(true)
    .opacity(0.3)
    .padding(.vertical, 5)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
}

private func controlSection(
    title: String,
    leadingSymbol: String,
    trailingSymbol: String,
    value: Binding<Double>,
    isMuted: Bool
) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(1)
            .help(title)
        MenuLevelMeter(
            title: title,
            value: value,
            isMuted: isMuted,
            leadingSymbol: leadingSymbol,
            trailingSymbol: trailingSymbol
        )
        .accessibilityLabel(title)
    }
    .padding(.vertical, 5)
}


private struct MenuLevelMeter: View {
    let title: String
    @Binding var value: Double
    let isMuted: Bool
    let leadingSymbol: String
    let trailingSymbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 14))
                .frame(width: 18)
            Slider(value: Binding(
                get: { isMuted ? 0 : value },
                set: { value = $0 }
            ), in: 0...100) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(isMuted ? "Muted" : "\(Int(value.rounded())) percent")
            Image(systemName: trailingSymbol)
                .font(.system(size: 16))
                .frame(width: 22)
        }
        .frame(minHeight: 24)
        .foregroundStyle(.primary.opacity(0.92))
    }
}
