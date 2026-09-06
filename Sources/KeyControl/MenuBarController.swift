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
                          model.launchAtLogin.objectWillChange.eraseToAnyPublisher(),
                          updates.objectWillChange.eraseToAnyPublisher()] {
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }
                .store(in: &observations)
        }
        refresh()
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
        let displays = model.brightness.displays
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
                displayRows[display.id] = row
                displayContainer.addSubview(row)
            }
            row.frame.origin.y = CGFloat(displays.count - index - 1) * 62
            row.update(title: display.name, value: Double(display.percent), enabled: model.brightness.isEnabled && display.canAdjust)
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
}

/// Standard AppKit controls inherit menu appearance and the user's system accent.
@MainActor
private final class NativeMenuSlider: NSView {
    let slider: NSSlider
    private let titleLabel = NSTextField(labelWithString: "")

    init(leading: String, trailing: String, target: AnyObject, action: Selector) {
        slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: target, action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: 62))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 14, y: 36, width: 276, height: 18)
        addSubview(titleLabel)
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
}
