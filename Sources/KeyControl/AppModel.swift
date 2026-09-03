import AppKit
import ApplicationServices
import Combine
import KeyControlCore

@MainActor
final class AppModel: ObservableObject {
    let audio = AudioController()
    let brightness = DDCController()
    let launchAtLogin = LaunchAtLoginController()

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
            self.brightness.nudge(isUp ? Level.defaultStep : -Level.defaultStep)
        }
    }
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastBrightnessMediaEvent = TimeInterval.zero
    private var started = false
    private let diagnosticsDefaults = UserDefaults.standard

    func start() {
        guard !started else { return }
        started = true
        audio.start()
        brightness.rediscover()
        let shouldPrompt = !diagnosticsDefaults.bool(forKey: "didRequestAccessibility")
        configureKeyCapture(prompt: shouldPrompt)
        if shouldPrompt {
            diagnosticsDefaults.set(true, forKey: "didRequestAccessibility")
            diagnosticsDefaults.synchronize()
        }
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
        audio.stop()
        started = false
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        if hasAccessibilityPermission { _ = keyTap.start() }
    }

    func requestInputMonitoring() {
        _ = BrightnessKeyListener.requestPermission()
        diagnosticsDefaults.set(true, forKey: "didRequestInputMonitoring")
        hasInputMonitoringPermission = BrightnessKeyListener.hasPermission
        diagnosticsDefaults.set(hasInputMonitoringPermission, forKey: "runtimeInputMonitoringGranted")
        diagnosticsDefaults.synchronize()
        updateBrightnessListener()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func configureKeyCapture(prompt: Bool) {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if !hasAccessibilityPermission, prompt {
            requestAccessibility()
        }
        if hasAccessibilityPermission, !keyTap.isRunning {
            _ = keyTap.start()
        }
        diagnosticsDefaults.set(hasAccessibilityPermission, forKey: "runtimeAccessibilityTrusted")
        diagnosticsDefaults.set(keyTap.isRunning, forKey: "runtimeEventTapRunning")
        diagnosticsDefaults.synchronize()
    }

    private func updateBrightnessListener() {
        hasInputMonitoringPermission = BrightnessKeyListener.hasPermission
        let needsRawKeys = brightness.isEnabled
            && brightness.isAvailable
            && !brightness.hasActiveBuiltInDisplay
        if needsRawKeys,
           !hasInputMonitoringPermission,
           !diagnosticsDefaults.bool(forKey: "didRequestInputMonitoring") {
            _ = BrightnessKeyListener.requestPermission()
            diagnosticsDefaults.set(true, forKey: "didRequestInputMonitoring")
            hasInputMonitoringPermission = BrightnessKeyListener.hasPermission
        }
        diagnosticsDefaults.set(hasInputMonitoringPermission, forKey: "runtimeInputMonitoringGranted")
        diagnosticsDefaults.synchronize()
        if needsRawKeys, hasInputMonitoringPermission {
            brightnessListener.start()
        } else {
            brightnessListener.stop()
        }
        diagnosticsDefaults.set(brightnessListener.isRunning, forKey: "runtimeBrightnessHIDRunning")
        diagnosticsDefaults.synchronize()
    }

    private func handle(_ key: MediaKey, fine: Bool) {
        diagnosticsDefaults.set(String(describing: key), forKey: "runtimeLastMediaKey")
        diagnosticsDefaults.set(
            diagnosticsDefaults.integer(forKey: "runtimeMediaKeyCount") + 1,
            forKey: "runtimeMediaKeyCount"
        )
        diagnosticsDefaults.synchronize()
        let step = fine ? 1 : Level.defaultStep
        switch key {
        case .volumeUp: audio.nudgeVolume(step)
        case .volumeDown: audio.nudgeVolume(-step)
        case .mute: audio.toggleMute()
        case .brightnessUp:
            lastBrightnessMediaEvent = ProcessInfo.processInfo.systemUptime
            brightness.nudge(step)
        case .brightnessDown:
            lastBrightnessMediaEvent = ProcessInfo.processInfo.systemUptime
            brightness.nudge(-step)
        }
    }
}
