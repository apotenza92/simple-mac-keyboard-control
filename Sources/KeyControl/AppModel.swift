import AppKit
import ApplicationServices
import Combine
import KeyControlCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let audio = AudioController()
    let brightness = DDCController()
    let launchAtLogin = LaunchAtLoginController()
    private let osd = OSDPresenter()

    @Published private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    @Published private(set) var hasInputMonitoringPermission = BrightnessKeyListener.hasPermission

    private lazy var keyTap = MediaKeyTap { [weak self] key, fine in
        self?.handle(key, fine: fine)
    }
    private lazy var brightnessListener = BrightnessKeyListener { [weak self] isUp in
        Task { @MainActor in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard ProcessInfo.processInfo.systemUptime - self.lastBrightnessMediaEvent > 0.1 else { return }
            self.brightness.nudge(isUp ? Level.defaultStep : -Level.defaultStep) { [weak self] in
                self?.showBrightnessOSD()
            }
        }
    }
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastBrightnessMediaEvent = TimeInterval.zero
    private var started = false
    private var setupWindow: NSWindow?
    private let diagnosticsDefaults = UserDefaults.standard

    func start() {
        guard !started else { return }
        started = true
        // Existing installs keep their behaviour. Fresh installs start with an
        // explanation, and request access only from the corresponding button.
        let needsSetup = !diagnosticsDefaults.bool(forKey: "didRequestAccessibility")
            && !diagnosticsDefaults.bool(forKey: "hasCompletedSetup")
        if !needsSetup { audio.start() }
        brightness.rediscover()
        configureKeyCapture(prompt: false)
        updateBrightnessListener()

        keyTap.shouldConsumeVolume = { [weak self] in
            MainActor.assumeIsolated { self?.audio.isApplyingSoftwareGain ?? false }
        }
        keyTap.shouldHandleBrightness = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return self.brightness.isAvailable
            }
        }

        keyTap.shouldConsumeBrightness = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return self.brightness.shouldConsumeBrightnessKeys
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.configureKeyCapture(prompt: false)
                self?.updateBrightnessListener()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.brightness.rediscover()
                self?.updateBrightnessListener()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.audio.stop() }
        })
        if needsSetup || ProcessInfo.processInfo.arguments.contains("--onboarding") { showSetupGuide() }
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.audio.start()
                self?.brightness.rediscover()
                self?.updateBrightnessListener()
            }
        })
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        keyTap.stop()
        brightnessListener.stop()
        brightness.stop()
        audio.stop()
        started = false
    }

    func requestAccessibility() {
        diagnosticsDefaults.set(true, forKey: "didRequestAccessibility")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        if hasAccessibilityPermission { _ = keyTap.start() }
    }

    func requestInputMonitoring() {
        _ = BrightnessKeyListener.requestPermission()
        diagnosticsDefaults.set(true, forKey: "didRequestInputMonitoring")
        let granted = BrightnessKeyListener.hasPermission
        if hasInputMonitoringPermission != granted { hasInputMonitoringPermission = granted }
        diagnosticsDefaults.set(hasInputMonitoringPermission, forKey: "runtimeInputMonitoringGranted")
        updateBrightnessListener()
    }

    enum PrivacyPane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case systemAudio = "Privacy_ScreenCapture"
    }

    func openPrivacySettings(_ pane: PrivacyPane) {
        let base = "x-apple.systempreferences:com.apple.preference.security"
        guard let target = URL(string: "\(base)?\(pane.rawValue)") else { return }
        if !NSWorkspace.shared.open(target), let fallback = URL(string: "\(base)?Privacy") {
            NSWorkspace.shared.open(fallback)
        }
    }

    func showSetupGuide() {
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SetupGuideView.windowSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set up \(AppIdentity.name)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupGuideView(model: self))
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishSetup() {
        diagnosticsDefaults.set(true, forKey: "hasCompletedSetup")
        setupWindow?.close()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    var brightnessDeviceName: String {
        guard let displayID = brightness.targetDisplayID else { return "Display Brightness" }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == displayID
        }?.localizedName ?? "Display Brightness"
    }

    private func configureKeyCapture(prompt: Bool) {
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted { hasAccessibilityPermission = trusted }
        if !hasAccessibilityPermission, prompt {
            requestAccessibility()
        }
        if hasAccessibilityPermission, !keyTap.isRunning {
            _ = keyTap.start()
        }
        diagnosticsDefaults.set(hasAccessibilityPermission, forKey: "runtimeAccessibilityTrusted")
        diagnosticsDefaults.set(keyTap.isRunning, forKey: "runtimeEventTapRunning")
    }

    private func updateBrightnessListener() {
        let granted = BrightnessKeyListener.hasPermission
        if hasInputMonitoringPermission != granted { hasInputMonitoringPermission = granted }
        let needsRawKeys = brightness.isEnabled
            && brightness.isAvailable
            && !brightness.hasActiveBuiltInDisplay
        diagnosticsDefaults.set(hasInputMonitoringPermission, forKey: "runtimeInputMonitoringGranted")
        if needsRawKeys, hasInputMonitoringPermission {
            brightnessListener.start()
        } else {
            brightnessListener.stop()
        }
        diagnosticsDefaults.set(brightnessListener.isRunning, forKey: "runtimeBrightnessHIDRunning")
    }

    private func handle(_ key: MediaKey, fine: Bool) {
        diagnosticsDefaults.set(String(describing: key), forKey: "runtimeLastMediaKey")
        diagnosticsDefaults.set(
            diagnosticsDefaults.integer(forKey: "runtimeMediaKeyCount") + 1,
            forKey: "runtimeMediaKeyCount"
        )
        let step = fine ? 1 : Level.defaultStep
        switch key {
        case .volumeUp:
            audio.nudgeVolume(step)
            showVolumeOSD()
        case .volumeDown:
            audio.nudgeVolume(-step)
            showVolumeOSD()
        case .mute:
            audio.toggleMute()
            showVolumeOSD()
        case .brightnessUp:
            lastBrightnessMediaEvent = ProcessInfo.processInfo.systemUptime
            brightness.nudge(step) { [weak self] in self?.showBrightnessOSD() }
        case .brightnessDown:
            lastBrightnessMediaEvent = ProcessInfo.processInfo.systemUptime
            brightness.nudge(-step) { [weak self] in self?.showBrightnessOSD() }
        }
    }

    private func showVolumeOSD() {
        let kind: OSDPresenter.Kind = audio.level.isMuted ? .muted : .volume
        let name = audio.deviceName ?? "Volume"
        let percent = audio.level.percent
        DispatchQueue.main.async { [weak self] in
            self?.osd.show(kind: kind, name: name, percent: percent)
        }
    }

    private func showBrightnessOSD() {
        guard brightness.isEnabled, brightness.isAvailable else { return }
        for displayID in brightness.controlledDisplayIDs {
            guard let display = brightness.displays.first(where: { $0.id == displayID }) else { continue }
            osd.show(kind: .brightness, name: display.name, percent: display.percent, displayID: displayID)
        }
    }
}
