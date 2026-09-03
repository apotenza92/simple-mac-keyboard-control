import Foundation

@MainActor
public final class AudioController: ObservableObject {
    public enum State: Equatable {
        case stopped
        case native(device: String)
        case active(device: String)
        case failed(device: String?, reason: String)
    }

    @Published public private(set) var level: Level
    @Published public private(set) var state: State = .stopped {
        didSet { publishRuntimeState() }
    }
    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            refresh()
        }
    }

    private enum Keys {
        static let enabled = "audioEnabled"
        static let percent = "volumePercent"
        static let muted = "volumeMuted"
        static let runtimeState = "runtimeAudioState"
        static let runtimeDevice = "runtimeAudioDevice"
        static let runtimeReason = "runtimeAudioReason"
    }

    private let defaults: UserDefaults
    private var pipeline: AudioPipeline?
    private var refreshTimer: Timer?
    private var activeDeviceUID: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.enabled: true, Keys.percent: 50, Keys.muted: false])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        level = Level(percent: defaults.integer(forKey: Keys.percent), isMuted: defaults.bool(forKey: Keys.muted))
    }

    public var isApplyingSoftwareGain: Bool {
        if case .active = state { return true }
        return false
    }

    public func start() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDeviceChanged() }
        }
    }

    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        pipeline?.destroy()
        pipeline = nil
        activeDeviceUID = nil
        state = .stopped
    }

    public func setVolume(_ percent: Int) {
        level.set(percent)
        applyLevel()
    }

    public func nudgeVolume(_ delta: Int) {
        level.nudge(delta)
        applyLevel()
    }

    public func toggleMute() {
        level.toggleMute()
        applyLevel()
    }

    public func refresh() {
        pipeline?.destroy()
        pipeline = nil
        activeDeviceUID = nil

        guard isEnabled else {
            state = .stopped
            return
        }
        guard let output = AudioHardware.defaultOutput() else {
            state = .failed(device: nil, reason: "No output device is available.")
            return
        }
        activeDeviceUID = output.uid

        // Let macOS own devices that already implement volume. The event tap
        // passes their keys through unchanged.
        guard !AudioHardware.hasNativeVolume(output) else {
            state = .native(device: output.name)
            return
        }
        guard let process = AudioHardware.processObject() else {
            state = .failed(device: output.name, reason: "Core Audio could not identify KeyControl.")
            return
        }

        do {
            let pipeline = try AudioPipeline(output: output, excluding: process, gain: level.gain)
            try pipeline.start()
            self.pipeline = pipeline
            state = .active(device: output.name)
        } catch {
            pipeline?.destroy()
            pipeline = nil
            state = .failed(device: output.name, reason: error.localizedDescription)
        }
    }

    private func applyLevel() {
        defaults.set(level.percent, forKey: Keys.percent)
        defaults.set(level.isMuted, forKey: Keys.muted)
        pipeline?.gain = level.gain
        defaults.synchronize()
        objectWillChange.send()
    }

    private func publishRuntimeState() {
        switch state {
        case .stopped:
            defaults.set("stopped", forKey: Keys.runtimeState)
            defaults.removeObject(forKey: Keys.runtimeDevice)
            defaults.removeObject(forKey: Keys.runtimeReason)
        case .native(let device):
            defaults.set("native", forKey: Keys.runtimeState)
            defaults.set(device, forKey: Keys.runtimeDevice)
            defaults.removeObject(forKey: Keys.runtimeReason)
        case .active(let device):
            defaults.set("active", forKey: Keys.runtimeState)
            defaults.set(device, forKey: Keys.runtimeDevice)
            defaults.removeObject(forKey: Keys.runtimeReason)
        case .failed(let device, let reason):
            defaults.set("failed", forKey: Keys.runtimeState)
            defaults.set(device, forKey: Keys.runtimeDevice)
            defaults.set(reason, forKey: Keys.runtimeReason)
        }
        defaults.synchronize()
    }

    private func refreshIfDeviceChanged() {
        guard AudioHardware.defaultOutput()?.uid != activeDeviceUID else { return }
        refresh()
    }
}
