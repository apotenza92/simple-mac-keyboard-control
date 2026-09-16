import AppKit
import Combine
import KeyControlCore

/// System menu rows own actions and appearance; only level controls need custom views.
@MainActor
final class MenuBarController: NSObject, ObservableObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let model: AppModel
    private let updates: UpdateManager
    private var observations = Set<AnyCancellable>()
    private var previousApplication: NSRunningApplication?
    private var volumeItem = NSMenuItem()
    private var brightnessItem = NSMenuItem()
    private var linkItem = NSMenuItem()
    private var loginItem = NSMenuItem()
    private var checkItem = NSMenuItem()
    private var updateItem = NSMenuItem()
    private var loginErrorItem = NSMenuItem()
    private var displayErrorItem = NSMenuItem()
    private var accessibilityItem = NSMenuItem()
    private var inputItem = NSMenuItem()
    private var audioItem = NSMenuItem()
    private var scheduleItems: [NSMenuItem] = []
    private var audioRow: NativeMenuSlider!
    private let displayContainer = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 62))
    private var displayRows: [UInt32: NativeMenuSlider] = [:]

    init(model: AppModel, updates: UpdateManager) {
        self.model = model
        self.updates = updates
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        let title = NSMenuItem(title: AppIdentity.name, action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: AppIdentity.name,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        title.isEnabled = false
        menu.addItem(title)
        volumeItem = checkbox("Volume keys", #selector(toggleVolume))
        menu.addItem(volumeItem)
        audioRow = NativeMenuSlider(leading: "speaker.fill", trailing: "speaker.wave.3.fill", target: self, action: #selector(adjustVolume(_:)))
        let audioSliderItem = NSMenuItem()
        audioSliderItem.view = audioRow
        menu.addItem(audioSliderItem)
        menu.addItem(.separator())
        brightnessItem = checkbox("Brightness keys", #selector(toggleBrightness))
        linkItem = checkbox("Link brightness", #selector(toggleLink))
        menu.addItem(brightnessItem)
        menu.addItem(linkItem)
        let displaysItem = NSMenuItem()
        displaysItem.view = displayContainer
        menu.addItem(displaysItem)
        displayErrorItem.title = "Couldn’t change display"
        displayErrorItem.isEnabled = false
        displayErrorItem.isHidden = true
        menu.addItem(displayErrorItem)
        menu.addItem(.separator())
        updateItem = NSMenuItem(title: "Check for updates", action: nil, keyEquivalent: "")
        let scheduleMenu = NSMenu()
        scheduleMenu.autoenablesItems = false
        for schedule in UpdateCheckSchedule.allCases {
            let item = action(schedule.title, #selector(selectSchedule(_:)))
            item.representedObject = schedule.rawValue
            scheduleItems.append(item)
            scheduleMenu.addItem(item)
        }
        updateItem.submenu = scheduleMenu
        menu.addItem(updateItem)
        checkItem = action("Check now…", #selector(checkNow))
        menu.addItem(checkItem)
        menu.addItem(.separator())
        loginItem = checkbox("Launch at login", #selector(toggleLogin))
        menu.addItem(loginItem)
        loginErrorItem.isEnabled = false
        menu.addItem(loginErrorItem)
        menu.addItem(action("Quit", #selector(quit), key: "q"))
        menu.addItem(.separator())
        let permissions = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permissionMenu = NSMenu()
        permissionMenu.autoenablesItems = false
        permissionMenu.delegate = self
        accessibilityItem = action(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? "Device Control…" : "Accessibility…", #selector(allowAccessibility))
        inputItem = action("Input Monitoring…", #selector(allowInput))
        audioItem = action("Allow System Audio Recording…", #selector(allowAudio))
        for item in [accessibilityItem, inputItem, audioItem] { permissionMenu.addItem(item) }
        permissions.submenu = permissionMenu
        menu.addItem(permissions)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(openMenu)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.image = AppIdentity.menuImage
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(AppIdentity.name)
            button.toolTip = AppIdentity.name
        }
        for publisher in [model.objectWillChange.eraseToAnyPublisher(),
                          model.audio.objectWillChange.eraseToAnyPublisher(),
                          model.brightness.objectWillChange.eraseToAnyPublisher(),
                          model.displayConnections.objectWillChange.eraseToAnyPublisher(),
                          model.launchAtLogin.objectWillChange.eraseToAnyPublisher(),
                          updates.objectWillChange.eraseToAnyPublisher()] {
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }
                .store(in: &observations)
        }
        refresh()
        if Bundle.main.bundleIdentifier == "com.apotenza.KeyControl.dev",
           ProcessInfo.processInfo.arguments.contains("--display-menu-smoke") {
            Task { await self.runDisplayMenuSmoke() }
        }
        if Bundle.main.bundleIdentifier == "com.apotenza.KeyControl.dev",
           ProcessInfo.processInfo.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                button.performClick(nil)
            }
        }
    }

    @objc private func openMenu() {
        guard let button = statusItem.button else { return }
        // AppKit draws embedded controls as inactive unless their application is
        // active. Activate before tracking starts, rather than recoloring cells.
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        statusItem.menu = menu
        button.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func menuDidClose(_ closedMenu: NSMenu) {
        guard closedMenu === menu else { return }
        statusItem.menu = nil
        // Assigning a status menu replaces the button's action. Restore our
        // activation path for every subsequent opening, including right-click.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openMenu)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        let previous = previousApplication
        previousApplication = nil
        // Do not steal focus back if the user selected a different application.
        if NSApp.isActive, previous?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous?.activate(options: [])
        }
    }

    private func refresh() {
        setCheckbox(volumeItem, checked: model.audio.isEnabled)
        setCheckbox(brightnessItem, checked: model.brightness.isEnabled)
        setCheckbox(linkItem, checked: model.brightness.isLinked, enabled: model.brightness.isEnabled)
        audioRow.update(title: model.audio.isEnabled ? (model.audio.deviceName ?? "Audio Output") : "Volume keys off",
                        value: model.audio.level.isMuted ? 0 : Double(model.audio.level.percent),
                        enabled: model.audio.isEnabled && model.audio.canAdjustVolume)
        refreshDisplays()
        displayErrorItem.isHidden = model.displayConnections.errorMessage == nil
        displayErrorItem.toolTip = model.displayConnections.errorMessage
        linkItem.isHidden = model.brightness.displays.count < 2
        linkItem.isEnabled = model.brightness.isEnabled
        setCheckbox(loginItem, checked: model.launchAtLogin.isEnabled)
        loginErrorItem.title = model.launchAtLogin.errorMessage ?? ""
        loginErrorItem.isHidden = model.launchAtLogin.errorMessage == nil
        updateItem.title = "Updates: " + updates.schedule.title
        updateItem.isEnabled = updates.isAvailable
        checkItem.isEnabled = updates.canCheckForUpdates
        for item in scheduleItems {
            item.state = item.representedObject as? String == updates.schedule.rawValue ? .on : .off
            item.isEnabled = updates.isAvailable
        }
        accessibilityItem.state = model.hasAccessibilityPermission ? .on : .off
        inputItem.state = model.hasInputMonitoringPermission ? .on : .off
        audioItem.state = model.audio.isApplyingSoftwareGain ? .on : .off
        audioItem.title = model.audio.isApplyingSoftwareGain ? "System Audio Recording" : "Allow System Audio Recording…"
        audioItem.isEnabled = !model.audio.isApplyingSoftwareGain
        if case .native = model.audio.state { audioItem.isHidden = true }
        else { audioItem.isHidden = !model.audio.isEnabled }
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }
    @objc private func toggleVolume() { model.audio.isEnabled.toggle() }
    @objc private func toggleBrightness() { model.brightness.isEnabled.toggle() }
    @objc private func toggleLink() { model.brightness.isLinked.toggle() }
    @objc private func toggleLogin() { model.launchAtLogin.setEnabled(!model.launchAtLogin.isEnabled) }
    @objc private func checkNow() { updates.checkForUpdates() }
    @objc private func quit() { model.quit() }
    @objc private func selectSchedule(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let schedule = UpdateCheckSchedule(rawValue: raw) else { return }
        updates.setSchedule(schedule)
    }
    @objc private func allowAccessibility() {
        if !model.hasAccessibilityPermission { model.requestAccessibility() }
        model.openPrivacySettings(.accessibility)
    }
    @objc private func allowInput() {
        if !model.hasInputMonitoringPermission { model.requestInputMonitoring() }
        model.openPrivacySettings(.inputMonitoring)
    }
    @objc private func allowAudio() { model.requestSystemAudio() }

    private func checkbox(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 28))
        let button = NSButton(checkboxWithTitle: title, target: self, action: selector)
        button.frame = NSRect(x: 14, y: 3, width: 276, height: 22)
        button.font = .menuFont(ofSize: 0)
        row.addSubview(button)
        item.view = row
        return item
    }

    private func setCheckbox(_ item: NSMenuItem, checked: Bool, enabled: Bool = true) {
        item.isEnabled = enabled
        guard let button = item.view?.subviews.first as? NSButton else { return }
        button.state = checked ? .on : .off
        button.isEnabled = enabled
    }

    private func refreshDisplays() {
        // The online brightness list loses disabled displays. Connection inventory
        // retains them; brightness remains a separate capability and key toggle.
        let brightness = model.brightness.displays
        let displays = model.displayConnections.displays.isEmpty
            ? brightness.map { DisplayConnectionController.Display(id: $0.id, key: "", name: $0.name,
                isEnabled: true, canToggle: false, physical: false) }
            : model.displayConnections.displays
        let ids = Set(displays.map(\.id))
        for id in Array(displayRows.keys) where !ids.contains(id) {
            displayRows.removeValue(forKey: id)?.removeFromSuperview()
        }
        for (index, display) in displays.enumerated() {
            let row: NativeMenuSlider
            if let existing = displayRows[display.id] { row = existing }
            else {
                row = NativeMenuSlider(leading: "sun.min.fill", trailing: "sun.max.fill", target: self, action: #selector(adjustBrightness(_:)))
                row.slider.tag = Int(display.id)
                row.displayToggle.target = self
                row.displayToggle.action = #selector(toggleDisplay(_:))
                displayRows[display.id] = row
                displayContainer.addSubview(row)
            }
            row.frame.origin.y = CGFloat(displays.count - index - 1) * 62
            let level = brightness.first { $0.id == display.id }
            row.update(title: display.name, value: Double(level?.percent ?? 100),
                enabled: display.isEnabled && model.brightness.isEnabled && level?.canAdjust == true)
            row.updateDisplayToggle(key: display.key, title: display.name,
                visible: model.displayConnections.showsCheckboxes && display.physical,
                checked: display.isEnabled,
                enabled: display.canToggle && !model.displayConnections.isChanging)
        }
        let height = CGFloat(displays.count) * 62
        if displayContainer.frame.height != height {
            displayContainer.setFrameSize(NSSize(width: 304, height: height))
            menu.update()
        }
    }

    @objc private func adjustVolume(_ sender: NSSlider) {
        model.audio.setVolume(Int(sender.doubleValue.rounded()))
    }
    @objc private func adjustBrightness(_ sender: NSSlider) {
        model.brightness.set(Int(sender.doubleValue.rounded()), for: UInt32(sender.tag))
    }
    @objc private func toggleDisplay(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        model.displayConnections.setEnabled(sender.state == .on, for: key)
    }

    /// Development integration test: native target/actions, no synthetic global
    /// input, no production automation interface and no saved display preference.
    private func runDisplayMenuSmoke() async {
        let defaults = UserDefaults.standard
        let brightnessWasEnabled = model.brightness.isEnabled
        var checks: [String] = []
        defaults.set("running", forKey: "runtimeDisplayMenuSmokeStatus")
        defaults.removeObject(forKey: "runtimeDisplayMenuSmokeError")
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "DisplayMenuSmoke", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(false, "Timed out waiting for display state.")
        }
        do {
            try await wait { self.model.displayConnections.displays.count == 2 }
            refresh()
            let displays = model.displayConnections.displays
            guard let builtIn = displays.first(where: { CGDisplayIsBuiltin($0.id) != 0 }),
                  let external = displays.first(where: { CGDisplayIsBuiltin($0.id) == 0 }) else {
                throw NSError(domain: "DisplayMenuSmoke", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Requires an open MacBook and one external display."])
            }
            for display in displays {
                let button = displayRows[display.id]!.displayToggle
                try require(!button.isHidden && button.state == .on && button.isEnabled, "Initial checkbox state is incorrect.")
                try require(button.toolTip == "Enable or Disable this display.", "Tooltip text differs.")
            }
            checks.append("two-visible-checked-controls-and-exact-tooltip")
            for target in [builtIn, external] {
                let survivor = target.id == builtIn.id ? external : builtIn
                if target.id == external.id { model.brightness.isEnabled = false }
                refresh()
                displayRows[target.id]!.displayToggle.performClick(nil)
                try await wait { !self.model.displayConnections.isChanging && self.model.displayConnections.displays.first { $0.key == target.key }?.isEnabled == false }
                refresh()
                try require(displayRows[target.id]!.displayToggle.state == .off, "Disabled display row disappeared or stayed checked.")
                try require(displayRows[target.id]!.displayToggle.isEnabled, "Cannot re-enable disabled display.")
                try require(!displayRows[target.id]!.slider.isEnabled, "Disabled display's brightness slider is still enabled.")
                try require(!displayRows[survivor.id]!.displayToggle.isEnabled, "Last-display checkbox is not protected.")
                // Bypass the disabled button to also test the controller/API guard.
                model.displayConnections.setEnabled(false, for: survivor.key)
                try await wait { !self.model.displayConnections.isChanging }
                try require(model.displayConnections.displays.first { $0.key == survivor.key }?.isEnabled == true,
                    "Last active display was disabled.")
                try require(model.displayConnections.errorMessage != nil, "Rejected operation did not report an error.")
                refresh()
                displayRows[target.id]!.displayToggle.performClick(nil)
                try await wait { !self.model.displayConnections.isChanging && self.model.displayConnections.displays.allSatisfy(\.isEnabled) }
                checks.append("native-checkbox-off-on-last-display-guard-\(target.name)")
            }
            model.brightness.isEnabled = brightnessWasEnabled
            checks.append("display-switching-independent-of-brightness-toggle")
            let crash = ProcessInfo.processInfo.arguments.contains("--display-menu-crash")
            let quit = ProcessInfo.processInfo.arguments.contains("--display-menu-quit")
            if crash || quit {
                refresh()
                displayRows[builtIn.id]!.displayToggle.performClick(nil)
                try await wait { !self.model.displayConnections.isChanging && self.model.displayConnections.displays.first { $0.key == builtIn.key }?.isEnabled == false }
                checks.append(crash ? "actual-app-ready-for-SIGKILL-with-display-disabled" : "actual-app-ready-for-quit-with-display-disabled")
                defaults.set(checks, forKey: "runtimeDisplayMenuSmokeChecks")
                defaults.set(crash ? "ready-for-crash" : "ready-for-quit", forKey: "runtimeDisplayMenuSmokeStatus")
                defaults.synchronize()
                if crash { kill(getpid(), SIGKILL) }
                else { model.quit() }
                return
            }
            defaults.set(checks, forKey: "runtimeDisplayMenuSmokeChecks")
            defaults.set("passed", forKey: "runtimeDisplayMenuSmokeStatus")
        } catch {
            model.brightness.isEnabled = brightnessWasEnabled
            model.displayConnections.restoreAll()
            try? await wait { !self.model.displayConnections.isChanging }
            defaults.set(checks, forKey: "runtimeDisplayMenuSmokeChecks")
            defaults.set(error.localizedDescription, forKey: "runtimeDisplayMenuSmokeError")
            defaults.set("failed", forKey: "runtimeDisplayMenuSmokeStatus")
        }
    }
}

/// Standard AppKit controls inherit menu appearance and the user's system accent.
@MainActor
private final class NativeMenuSlider: NSView {
    let slider: NSSlider
    let displayToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")

    init(leading: String, trailing: String, target: AnyObject, action: Selector) {
        slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: target, action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: 62))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 14, y: 36, width: 276, height: 18)
        addSubview(titleLabel)
        displayToggle.frame = NSRect(x: 272, y: 35, width: 20, height: 20)
        displayToggle.isHidden = true
        displayToggle.toolTip = "Enable or Disable this display."
        addSubview(displayToggle)
        slider.isContinuous = true
        slider.frame = NSRect(x: 40, y: 6, width: 222, height: 24)
        addSubview(slider)
        for (symbol, x) in [(leading, 14.0), (trailing, 272.0)] {
            let image = NSImageView(frame: NSRect(x: x, y: 10, width: 18, height: 18))
            image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image.contentTintColor = .secondaryLabelColor
            addSubview(image)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, value: Double, enabled: Bool) {
        titleLabel.stringValue = title
        titleLabel.toolTip = title
        slider.setAccessibilityLabel(title)
        slider.doubleValue = value
        slider.isEnabled = enabled
    }

    func updateDisplayToggle(key: String, title: String, visible: Bool, checked: Bool, enabled: Bool) {
        displayToggle.identifier = NSUserInterfaceItemIdentifier(key)
        displayToggle.isHidden = !visible
        displayToggle.state = checked ? .on : .off
        displayToggle.isEnabled = enabled
        displayToggle.setAccessibilityLabel("Enable or Disable \(title)")
        titleLabel.frame.size.width = visible ? 250 : 276
    }
}
