import SwiftUI
import KeyControlCore

/// Shared by the menu and setup guide: one explanation and action per permission.
struct PermissionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var audio: AudioController
    @ObservedObject private var brightness: DDCController

    init(model: AppModel) {
        self.model = model
        audio = model.audio
        brightness = model.brightness
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permission(
                title: keyboardPermissionTitle,
                detail: "Volume and brightness keys",
                status: model.hasAccessibilityPermission ? nil : "Required",
                enabled: model.hasAccessibilityPermission,
                actionTitle: model.hasAccessibilityPermission ? "Open Settings" : "Allow…"
            ) {
                if !model.hasAccessibilityPermission { model.requestAccessibility() }
                model.openPrivacySettings(.accessibility)
            }

            Divider()

            permission(
                title: "Input Monitoring",
                detail: "External keyboard brightness keys",
                status: model.hasInputMonitoringPermission ? nil : (needsRawKeys ? "Needed" : "Optional"),
                enabled: model.hasInputMonitoringPermission,
                actionTitle: model.hasInputMonitoringPermission ? "Open Settings" : "Allow…"
            ) {
                if !model.hasInputMonitoringPermission { model.requestInputMonitoring() }
                model.openPrivacySettings(.inputMonitoring)
            }

            if needsSystemAudio {
                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            permissionHeading("System Audio Recording", status: nil,
                                              enabled: audio.isApplyingSoftwareGain)
                                .help("Audio status reflects the running pipeline, not a verified macOS permission grant.")
                            Text("Enables volume control.")
                                .font(.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 7) {
                            Button("Open Settings") { model.openPrivacySettings(.systemAudio) }
                            if canTryAudio {
                                Button("Try Audio") { audio.start() }
                            }
                        }
                        .controlSize(.regular)
                        .fixedSize()
                    }
                    if case .failed(_, let reason) = audio.state {
                        Text(reason).font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var keyboardPermissionTitle: String {
        if #available(macOS 27.0, *) {
            return "Device Control"
        }
        return "Accessibility"
    }

    private var needsRawKeys: Bool {
        brightness.isEnabled && brightness.isAvailable && !brightness.hasActiveBuiltInDisplay
    }

    private var needsSystemAudio: Bool {
        guard audio.isEnabled else { return false }
        if case .native = audio.state { return false }
        return true
    }

    private var canTryAudio: Bool {
        guard audio.isEnabled else { return false }
        switch audio.state {
        case .stopped, .failed: return true
        case .active, .native: return false
        }
    }

    private func permission(title: String, detail: String, status: String?,
                            enabled: Bool, actionTitle: String,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                permissionHeading(title, status: status, enabled: enabled)
                Text(detail).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .controlSize(.regular)
                .fixedSize()
        }
    }

    private func permissionHeading(_ title: String, status: String?, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel(enabled ? "Enabled" : "Not enabled")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    Text(status).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SetupGuideView: View {
    // Size the window for its controls; prose wraps within this content width.
    static let windowSize = NSSize(width: 420, height: 580)
    @ObservedObject var model: AppModel
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: step == 1 ? "lock.shield" : "keyboard")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.system(size: 25, weight: .bold))
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    switch step {
                    case 0:
                        VStack(alignment: .leading, spacing: 18) {
                            feature("speaker.wave.2", title: "Volume and mute",
                                    detail: "Use your keyboard with audio interfaces that lack Mac volume controls.")
                            Divider()
                            feature("sun.max", title: "Display brightness",
                                    detail: "Adjust compatible external monitors with your brightness keys.")
                        }
                        .padding(16)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    case 1:
                        PermissionsView(model: model)
                    default:
                        feature("menubar.rectangle", title: "Find us in the menu bar",
                                detail: "Adjust levels, check permissions, or quit. Nothing in your Dock.")
                        feature("keyboard", title: "Try your usual keys",
                                detail: "Press volume, mute, and brightness. Your hardware still needs to support the selected control.")
                        Text("Skipped a permission? You can enable it from the menu whenever you’re ready.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityLabel("Step \(step + 1) of 3")
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Button(step == 0 ? "Get Started" : step == 1 ? "Continue" : "Done") {
                    if step == 2 { model.finishSetup() } else { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var title: String {
        switch step {
        case 0: return "Your keyboard.\nYour hardware."
        case 1: return "Allow keyboard control"
        default: return "Make yourself at home"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "Welcome to \(AppIdentity.name)."
        case 1: return "Enable the access your setup needs. You can also do this later from the menu."
        default: return "A small utility, quietly in the background."
        }
    }

    private func feature(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 24)
                .foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
