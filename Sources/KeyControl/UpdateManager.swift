import AppKit
import Combine
import Foundation
import Sparkle

/// Each release identity stays on its own architecture-specific signed feed.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    private var observation: AnyCancellable?
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        if let test = UpdateTestSession.current,
           Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == test.expectedBuild {
            test.record("installed-and-relaunched:" + test.expectedBuild)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        guard ["com.apotenza.KeyControl", "com.apotenza.KeyControl.beta"].contains(Bundle.main.bundleIdentifier ?? ""),
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.startUpdater()
        if UpdateTestSession.current != nil {
            controller.updater.automaticallyDownloadsUpdates = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.updater.checkForUpdatesInBackground() }
        }
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateTestSession.current?.feedURL
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                            immediateInstallationBlock: @escaping () -> Void) -> Bool {
        guard UpdateTestSession.current != nil else { return false }
        immediateInstallationBlock()
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        UpdateTestSession.current?.record("error:" + error.localizedDescription)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
