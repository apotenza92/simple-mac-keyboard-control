import Combine
import Foundation
import Sparkle

/// Each release identity stays on its own architecture-specific signed feed.
@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var observation: AnyCancellable?
    private var controller: SPUStandardUpdaterController?

    init() {
        guard ["com.apotenza.KeyControl", "com.apotenza.KeyControl.beta"].contains(Bundle.main.bundleIdentifier ?? ""),
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
