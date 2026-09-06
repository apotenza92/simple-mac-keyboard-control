import AppKit

@main
@MainActor
final class KeyControlApp: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var updates: UpdateManager?
    private var menuBar: MenuBarController?

    static func main() {
        let application = NSApplication.shared
        let delegate = KeyControlApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        let updates = UpdateManager()
        self.model = model
        self.updates = updates
        if UpdateTestSession.current == nil {
            menuBar = MenuBarController(model: model, updates: updates)
            model.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}
