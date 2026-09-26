import AppKit

/// Island's preferences, shared between the app and its System Settings pane.
///
/// Both processes keep their own copy. Every change is written to the
/// `com.niranjan.Halo` defaults domain and broadcast as a distributed
/// notification carrying the key and value, so the other side updates at once
/// instead of waiting on preference caching.
@MainActor
public final class Settings: ObservableObject {
    public enum Context {
        case app
        case pane
    }

    public static let domain = "com.niranjan.Halo"
    public static let shared = Settings()

    static let changedNotification = Notification.Name("com.niranjan.Halo.settingChanged")
    static let commandNotification = Notification.Name("com.niranjan.Halo.command")
    static let statusNotification = Notification.Name("com.niranjan.Halo.status")

    public let context: Context
    private let defaults: UserDefaults
    private let sender = UUID().uuidString
    private var isApplyingRemoteChange = false

    // MARK: Preferences

    @Published public var isEnabled: Bool { didSet { store(isEnabled, .enabled) } }
    @Published public var clickExpands: Bool { didSet { store(clickExpands, .clickExpands) } }
    @Published public var expandOnHover: Bool { didSet { store(expandOnHover, .expandOnHover) } }
    @Published public var liquidGlass: Bool { didSet { store(liquidGlass, .liquidGlass) } }
    @Published public var replaceSystemHUD: Bool { didSet { store(replaceSystemHUD, .replaceSystemHUD) } }
    @Published public var showOnDisplaysWithoutNotch: Bool { didSet { store(showOnDisplaysWithoutNotch, .showOnDisplaysWithoutNotch) } }
    @Published public var haptics: Bool { didSet { store(haptics, .haptics) } }

    @Published public var showNowPlaying: Bool { didSet { store(showNowPlaying, .showNowPlaying) } }
    @Published public var showCalls: Bool { didSet { store(showCalls, .showCalls) } }
    @Published public var showVolume: Bool { didSet { store(showVolume, .showVolume) } }
    @Published public var showBrightness: Bool { didSet { store(showBrightness, .showBrightness) } }
    @Published public var showBattery: Bool { didSet { store(showBattery, .showBattery) } }
    @Published public var showBluetooth: Bool { didSet { store(showBluetooth, .showBluetooth) } }
    @Published public var showAudioOutput: Bool { didSet { store(showAudioOutput, .showAudioOutput) } }
    @Published public var showNetwork: Bool { didSet { store(showNetwork, .showNetwork) } }
    @Published public var showDownloads: Bool { didSet { store(showDownloads, .showDownloads) } }
    @Published public var showCapsLock: Bool { didSet { store(showCapsLock, .showCapsLock) } }
    @Published public var showPrivacy: Bool { didSet { store(showPrivacy, .showPrivacy) } }
    @Published public var showCalendar: Bool { didSet { store(showCalendar, .showCalendar) } }
    @Published public var rainAlerts: Bool { didSet { store(rainAlerts, .rainAlerts) } }
    @Published public var showWeather: Bool { didSet { store(showWeather, .showWeather) } }
    @Published public var hideInFullScreen: Bool { didSet { store(hideInFullScreen, .hideInFullScreen) } }

    @Published public var clipboardHistory: Bool { didSet { store(clipboardHistory, .clipboardHistory) } }

    /// The two tiles at the top of the Controls page: "battery", "focus", "weather" or "clipboard".
    @Published public var controlsLeftTile: String { didSet { store(controlsLeftTile, .controlsLeftTile) } }
    @Published public var controlsRightTile: String { didSet { store(controlsRightTile, .controlsRightTile) } }
    /// Comma-separated `ControlAction` names for the round buttons, in order; see `buttons`.
    @Published public var controlsButtons: String { didSet { store(controlsButtons, .controlsButtons) } }
    @Published public var showVolumeSlider: Bool { didSet { store(showVolumeSlider, .showVolumeSlider) } }
    /// An `IdlePage` name: what a click on the island opens when nothing is running.
    @Published public var idlePage: String { didSet { store(idlePage, .idlePage) } }
    /// Comma-separated `IslandPage` names that are switched on.
    @Published public var extraPages: String { didSet { store(extraPages, .extraPages) } }
    /// The original two wellbeing switches. They only seed `reminders` now, and are
    /// kept so an existing setup carries over rather than starting from scratch.
    @Published public var eyeBreaks: Bool { didSet { store(eyeBreaks, .eyeBreaks) } }
    @Published public var hydrationReminders: Bool { didSet { store(hydrationReminders, .hydrationReminders) } }
    /// The reminder list as JSON — see `reminders` for the typed way in and out.
    @Published public var remindersJSON: String { didSet { store(remindersJSON, .reminders) } }

    /// Every reminder the user has. Until they touch the list it is derived from the
    /// old eye-break and water switches, so an existing setup carries over untouched
    /// and only becomes a stored list once it is actually edited.
    public var reminders: [Reminder] {
        get { Reminder.decode(remindersJSON) ?? Reminder.defaults(eyeBreaks: eyeBreaks, water: hydrationReminders) }
        set { remindersJSON = Reminder.encode(newValue.map { $0.sanitised() }) }
    }
    /// A stretch of the day to keep reminders quiet, as minutes past midnight.
    @Published public var quietHoursOn: Bool { didSet { store(quietHoursOn, .quietHoursOn) } }
    @Published public var quietFrom: Int { didSet { store(quietFrom, .quietFrom) } }
    @Published public var quietTo: Int { didSet { store(quietTo, .quietTo) } }
    @Published public var alertPaceRaw: String { didSet { store(alertPaceRaw, .alertPace) } }
    @Published public var temperatureUnitRaw: String { didSet { store(temperatureUnitRaw, .temperatureUnit) } }

    public var quietHours: QuietHours {
        get { QuietHours(isOn: quietHoursOn, from: quietFrom, to: quietTo) }
        set {
            quietHoursOn = newValue.isOn
            quietFrom = newValue.from
            quietTo = newValue.to
        }
    }

    public var alertPace: AlertPace {
        get { AlertPace(rawValue: alertPaceRaw) ?? .normal }
        set { alertPaceRaw = newValue.rawValue }
    }

    public var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic }
        set { temperatureUnitRaw = newValue.rawValue }
    }

    /// Whether the user wants Halo at login. Kept separately from whether macOS
    /// currently has it registered: the registration is lost whenever the app's
    /// signature changes, and without a record of the intent there is nothing to
    /// put it back from.
    @Published public var opensAtLogin: Bool { didSet { store(opensAtLogin, .opensAtLogin) } }

    @Published public var timerSound: Bool { didSet { store(timerSound, .timerSound) } }
    /// New screenshots go straight onto the clipboard, ready for ⌘V.
    @Published public var copyScreenshots: Bool { didSet { store(copyScreenshots, .copyScreenshots) } }
    /// macOS saves screenshots into Island's folder instead of onto the Desktop.
    @Published public var screenshotsOffDesktop: Bool { didSet { store(screenshotsOffDesktop, .screenshotsOffDesktop) } }
    /// Keeps the compact island narrow enough not to cover menu bar icons.
    @Published public var avoidMenuBarIcons: Bool { didSet { store(avoidMenuBarIcons, .avoidMenuBarIcons) } }
    @Published public var showCopiedInIsland: Bool { didSet { store(showCopiedInIsland, .showCopiedInIsland) } }
    /// Empty means "work it out from this Mac" (location, or the time zone's city).
    @Published public var weatherCity: String { didSet { store(weatherCity, .weatherCity) } }

    // MARK: Status reported by the app

    @Published public private(set) var launchAtLogin = false
    @Published public private(set) var accessibilityGranted = false
    /// The raw SMAppService state, so the pane can tell "off" from "waiting for you
    /// to approve it in Login Items".
    @Published public private(set) var loginItemStatus = ""
    @Published public private(set) var isAppRunning = false

    /// Set by the app; runs commands that arrive from the System Settings pane.
    public var commandHandler: ((_ command: String, _ value: Bool) -> Void)?

    enum Key: String, CaseIterable {
        case enabled, clickExpands, expandOnHover, liquidGlass, replaceSystemHUD, showOnDisplaysWithoutNotch, haptics
        case showNowPlaying, showCalls, showVolume, showBrightness, showBattery, showBluetooth, showAudioOutput
        case showNetwork, showDownloads, showCapsLock, showPrivacy, showCalendar, showWeather, hideInFullScreen
        case weatherCity, clipboardHistory, showCopiedInIsland
        case controlsLeftTile, controlsRightTile, controlsButtons, showVolumeSlider, idlePage, avoidMenuBarIcons
        case rainAlerts, extraPages, eyeBreaks, hydrationReminders, timerSound, copyScreenshots, screenshotsOffDesktop
        case reminders, quietHoursOn, quietFrom, quietTo, alertPace, temperatureUnit, opensAtLogin
    }

    private init() {
        context = Bundle.main.bundleIdentifier == Self.domain ? .app : .pane
        defaults = context == .app ? .standard : (UserDefaults(suiteName: Self.domain) ?? .standard)

        // The app used to be called Island: bring its preferences across the first time.
        if context == .app, defaults.persistentDomain(forName: Self.domain) == nil,
           let old = defaults.persistentDomain(forName: "com.niranjan.Island") {
            defaults.setPersistentDomain(old, forName: Self.domain)
        }

        defaults.register(defaults: [
            Key.enabled.rawValue: true,
            Key.clickExpands.rawValue: true,
            Key.expandOnHover.rawValue: false,
            Key.liquidGlass.rawValue: true,
            Key.replaceSystemHUD.rawValue: true,
            Key.showOnDisplaysWithoutNotch.rawValue: true,
            Key.haptics.rawValue: true,
            Key.showNowPlaying.rawValue: true,
            Key.showCalls.rawValue: true,
            Key.showVolume.rawValue: true,
            Key.showBrightness.rawValue: true,
            Key.showBattery.rawValue: true,
            Key.showBluetooth.rawValue: true,
            Key.showAudioOutput.rawValue: true,
            Key.showNetwork.rawValue: true,
            Key.showDownloads.rawValue: true,
            Key.showCapsLock.rawValue: true,
            Key.showPrivacy.rawValue: true,
            Key.showCalendar.rawValue: false,
            Key.rainAlerts.rawValue: true,
            Key.showWeather.rawValue: false,
            Key.hideInFullScreen.rawValue: true,
            Key.clipboardHistory.rawValue: true,
            Key.controlsLeftTile.rawValue: "battery",
            Key.controlsRightTile.rawValue: "focus",
            Key.controlsButtons.rawValue: Self.defaultButtons,
            Key.showVolumeSlider.rawValue: true,
            Key.idlePage.rawValue: IdlePage.automatic.rawValue,
            Key.avoidMenuBarIcons.rawValue: true,
            Key.extraPages.rawValue: IslandPage.defaultPages,
            Key.eyeBreaks.rawValue: false,
            Key.hydrationReminders.rawValue: false,
            Key.timerSound.rawValue: true,
            Key.copyScreenshots.rawValue: true,
            Key.screenshotsOffDesktop.rawValue: true,
            Key.opensAtLogin.rawValue: true,
            Key.quietHoursOn.rawValue: false,
            Key.quietFrom.rawValue: QuietHours.defaultFrom,
            Key.quietTo.rawValue: QuietHours.defaultTo,
            Key.alertPace.rawValue: AlertPace.normal.rawValue,
            Key.temperatureUnit.rawValue: TemperatureUnit.automatic.rawValue,
            Key.showCopiedInIsland.rawValue: true,
            Key.weatherCity.rawValue: "",
        ])

        isEnabled = defaults.bool(forKey: Key.enabled.rawValue)
        clickExpands = defaults.bool(forKey: Key.clickExpands.rawValue)
        expandOnHover = defaults.bool(forKey: Key.expandOnHover.rawValue)
        liquidGlass = defaults.bool(forKey: Key.liquidGlass.rawValue)
        replaceSystemHUD = defaults.bool(forKey: Key.replaceSystemHUD.rawValue)
        showOnDisplaysWithoutNotch = defaults.bool(forKey: Key.showOnDisplaysWithoutNotch.rawValue)
        haptics = defaults.bool(forKey: Key.haptics.rawValue)
        showNowPlaying = defaults.bool(forKey: Key.showNowPlaying.rawValue)
        showCalls = defaults.bool(forKey: Key.showCalls.rawValue)
        showVolume = defaults.bool(forKey: Key.showVolume.rawValue)
        showBrightness = defaults.bool(forKey: Key.showBrightness.rawValue)
        showBattery = defaults.bool(forKey: Key.showBattery.rawValue)
        showBluetooth = defaults.bool(forKey: Key.showBluetooth.rawValue)
        showAudioOutput = defaults.bool(forKey: Key.showAudioOutput.rawValue)
        showNetwork = defaults.bool(forKey: Key.showNetwork.rawValue)
        showDownloads = defaults.bool(forKey: Key.showDownloads.rawValue)
        showCapsLock = defaults.bool(forKey: Key.showCapsLock.rawValue)
        showPrivacy = defaults.bool(forKey: Key.showPrivacy.rawValue)
        showCalendar = defaults.bool(forKey: Key.showCalendar.rawValue)
        rainAlerts = defaults.bool(forKey: Key.rainAlerts.rawValue)
        showWeather = defaults.bool(forKey: Key.showWeather.rawValue)
        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen.rawValue)
        clipboardHistory = defaults.bool(forKey: Key.clipboardHistory.rawValue)
        controlsLeftTile = defaults.string(forKey: Key.controlsLeftTile.rawValue) ?? "battery"
        controlsRightTile = defaults.string(forKey: Key.controlsRightTile.rawValue) ?? "focus"
        if defaults.object(forKey: Key.controlsButtons.rawValue) == nil,
           defaults.object(forKey: "showClipboardButton") != nil {
            // Carry over the on/off buttons from before the slots existed.
            let old = [("showClipboardButton", "clipboard"), ("showClearCachesButton", "clearCaches"), ("showForceQuitButton", "forceQuit")]
            let stored = defaults
            var slots = old.filter { stored.object(forKey: $0.0) as? Bool ?? true }.map(\.1)
            while slots.count < 4 { slots.append("none") }
            defaults.set(slots.joined(separator: ","), forKey: Key.controlsButtons.rawValue)
        }
        if defaults.string(forKey: Key.controlsButtons.rawValue) == "clipboard,clearCaches,forceQuit,none" {
            // The first release's untouched default; move it to the fuller set.
            defaults.set(Self.defaultButtons, forKey: Key.controlsButtons.rawValue)
        }
        controlsButtons = defaults.string(forKey: Key.controlsButtons.rawValue) ?? Self.defaultButtons
        showVolumeSlider = defaults.bool(forKey: Key.showVolumeSlider.rawValue)
        idlePage = defaults.string(forKey: Key.idlePage.rawValue) ?? IdlePage.automatic.rawValue
        avoidMenuBarIcons = defaults.bool(forKey: Key.avoidMenuBarIcons.rawValue)
        extraPages = defaults.string(forKey: Key.extraPages.rawValue) ?? IslandPage.defaultPages
        eyeBreaks = defaults.bool(forKey: Key.eyeBreaks.rawValue)
        remindersJSON = defaults.string(forKey: Key.reminders.rawValue) ?? ""
        opensAtLogin = defaults.bool(forKey: Key.opensAtLogin.rawValue)
        quietHoursOn = defaults.bool(forKey: Key.quietHoursOn.rawValue)
        quietFrom = defaults.integer(forKey: Key.quietFrom.rawValue)
        quietTo = defaults.integer(forKey: Key.quietTo.rawValue)
        alertPaceRaw = defaults.string(forKey: Key.alertPace.rawValue) ?? AlertPace.normal.rawValue
        temperatureUnitRaw = defaults.string(forKey: Key.temperatureUnit.rawValue)
            ?? TemperatureUnit.automatic.rawValue
        hydrationReminders = defaults.bool(forKey: Key.hydrationReminders.rawValue)
        timerSound = defaults.bool(forKey: Key.timerSound.rawValue)
        copyScreenshots = defaults.bool(forKey: Key.copyScreenshots.rawValue)
        screenshotsOffDesktop = defaults.bool(forKey: Key.screenshotsOffDesktop.rawValue)
        showCopiedInIsland = defaults.bool(forKey: Key.showCopiedInIsland.rawValue)
        weatherCity = defaults.string(forKey: Key.weatherCity.rawValue) ?? ""
        launchAtLogin = defaults.bool(forKey: "status.launchAtLogin")
        accessibilityGranted = defaults.bool(forKey: "status.accessibilityGranted")
        loginItemStatus = defaults.string(forKey: "status.loginItem") ?? ""

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.changedNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.receiveChange(info) }
        }
        switch context {
        case .app:
            center.addObserver(forName: Self.commandNotification, object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo
                MainActor.assumeIsolated {
                    guard let self, let command = info?["command"] as? String else { return }
                    if command == "requestStatus" {
                        self.broadcastStatus()
                    } else {
                        self.commandHandler?(command, info?["value"] as? Bool ?? false)
                    }
                }
            }
        case .pane:
            center.addObserver(forName: Self.statusNotification, object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isAppRunning = true
                    if let value = info?["launchAtLogin"] as? Bool { self.launchAtLogin = value }
                    if let value = info?["accessibilityGranted"] as? Bool { self.accessibilityGranted = value }
                    if let value = info?["loginItem"] as? String { self.loginItemStatus = value }
                }
            }
            refreshAppRunning()
            send(command: "requestStatus")
        }
    }

    // MARK: Syncing

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        guard !isApplyingRemoteChange else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.changedNotification, object: nil,
            userInfo: ["key": key.rawValue, "value": value, "sender": sender],
            deliverImmediately: true
        )
    }

    private func receiveChange(_ info: [AnyHashable: Any]?) {
        guard let info, info["sender"] as? String != sender,
              let rawKey = info["key"] as? String, let key = Key(rawValue: rawKey) else { return }
        let value = info["value"]
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        func assign(_ property: ReferenceWritableKeyPath<Settings, Bool>) {
            if let bool = value as? Bool, self[keyPath: property] != bool { self[keyPath: property] = bool }
        }
        func assign(_ property: ReferenceWritableKeyPath<Settings, Int>) {
            if let int = value as? Int, self[keyPath: property] != int { self[keyPath: property] = int }
        }
        func assign(_ property: ReferenceWritableKeyPath<Settings, String>) {
            if let text = value as? String, self[keyPath: property] != text { self[keyPath: property] = text }
        }

        switch key {
        case .enabled: assign(\.isEnabled)
        case .clickExpands: assign(\.clickExpands)
        case .expandOnHover: assign(\.expandOnHover)
        case .liquidGlass: assign(\.liquidGlass)
        case .replaceSystemHUD: assign(\.replaceSystemHUD)
        case .showOnDisplaysWithoutNotch: assign(\.showOnDisplaysWithoutNotch)
        case .haptics: assign(\.haptics)
        case .showNowPlaying: assign(\.showNowPlaying)
        case .showCalls: assign(\.showCalls)
        case .showVolume: assign(\.showVolume)
        case .showBrightness: assign(\.showBrightness)
        case .showBattery: assign(\.showBattery)
        case .showBluetooth: assign(\.showBluetooth)
        case .showAudioOutput: assign(\.showAudioOutput)
        case .showNetwork: assign(\.showNetwork)
        case .showDownloads: assign(\.showDownloads)
        case .showCapsLock: assign(\.showCapsLock)
        case .showPrivacy: assign(\.showPrivacy)
        case .showCalendar: assign(\.showCalendar)
        case .rainAlerts: assign(\.rainAlerts)
        case .showWeather: assign(\.showWeather)
        case .hideInFullScreen: assign(\.hideInFullScreen)
        case .clipboardHistory: assign(\.clipboardHistory)
        case .controlsLeftTile: assign(\.controlsLeftTile)
        case .controlsRightTile: assign(\.controlsRightTile)
        case .controlsButtons: assign(\.controlsButtons)
        case .showVolumeSlider: assign(\.showVolumeSlider)
        case .idlePage: assign(\.idlePage)
        case .avoidMenuBarIcons: assign(\.avoidMenuBarIcons)
        case .extraPages: assign(\.extraPages)
        case .eyeBreaks: assign(\.eyeBreaks)
        case .reminders: assign(\.remindersJSON)
        case .opensAtLogin: assign(\.opensAtLogin)
        case .quietHoursOn: assign(\.quietHoursOn)
        case .quietFrom: assign(\.quietFrom)
        case .quietTo: assign(\.quietTo)
        case .alertPace: assign(\.alertPaceRaw)
        case .temperatureUnit: assign(\.temperatureUnitRaw)
        case .hydrationReminders: assign(\.hydrationReminders)
        case .timerSound: assign(\.timerSound)
        case .copyScreenshots: assign(\.copyScreenshots)
        case .screenshotsOffDesktop: assign(\.screenshotsOffDesktop)
        case .showCopiedInIsland: assign(\.showCopiedInIsland)
        case .weatherCity: assign(\.weatherCity)
        }
    }

    // MARK: Status and commands

    /// App side: publish status for the pane (and remember it for the next time the pane opens).
    public func updateStatus(launchAtLogin: Bool, accessibilityGranted: Bool,
                             loginItemStatus: String = "") {
        if self.launchAtLogin != launchAtLogin { self.launchAtLogin = launchAtLogin }
        if self.accessibilityGranted != accessibilityGranted { self.accessibilityGranted = accessibilityGranted }
        if !loginItemStatus.isEmpty, self.loginItemStatus != loginItemStatus {
            self.loginItemStatus = loginItemStatus
        }
        defaults.set(launchAtLogin, forKey: "status.launchAtLogin")
        defaults.set(accessibilityGranted, forKey: "status.accessibilityGranted")
        defaults.set(loginItemStatus, forKey: "status.loginItem")
        broadcastStatus()
    }

    private func broadcastStatus() {
        guard context == .app else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.statusNotification, object: nil,
            userInfo: ["launchAtLogin": launchAtLogin, "accessibilityGranted": accessibilityGranted,
                       "loginItem": loginItemStatus],
            deliverImmediately: true
        )
    }

    /// Asks the app to do something only it can (it owns the login item and the
    /// Accessibility permission). In the app itself this runs directly.
    public func send(command: String, value: Bool = false) {
        switch context {
        case .app:
            commandHandler?(command, value)
        case .pane:
            DistributedNotificationCenter.default().postNotificationName(
                Self.commandNotification, object: nil,
                userInfo: ["command": command, "value": value],
                deliverImmediately: true
            )
        }
    }

    public func refreshAppRunning() {
        guard context == .pane else {
            isAppRunning = true
            return
        }
        isAppRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.domain).isEmpty
    }

    public var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }
}
