import AppKit
import Combine
import HaloCore
import SwiftUI

/// A borderless panel above the menu bar that never takes keyboard focus, so
/// clicking the island never pulls you out of the app you're typing in.
final class HaloPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Windows are normally kept below the menu bar; the island lives on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Lets the first click on the island act immediately instead of just focusing it.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// Horizontal trackpad swipes, reported once per gesture as -1 (left) or +1 (right).
    var onSwipe: ((Int) -> Void)?
    /// Vertical scrolling over the island; return true when it was used.
    var onVerticalScroll: ((CGFloat) -> Bool)?
    private var swipeDistance: CGFloat = 0
    private var swipeHandled = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || swipeDistance != 0 else {
            if onVerticalScroll?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8)) != true {
                super.scrollWheel(with: event)
            }
            return
        }
        if event.phase == .began {
            swipeDistance = 0
            swipeHandled = false
        }
        swipeDistance += event.scrollingDeltaX
        if !swipeHandled, abs(swipeDistance) > 50 {
            swipeHandled = true
            // Content follows the fingers: swiping left brings in the next page.
            onSwipe?(swipeDistance < 0 ? 1 : -1)
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            swipeDistance = 0
            swipeHandled = false
        }
    }
}

/// Owns the island window and wires every system monitor into the model.
@MainActor
final class IslandController {
    private let settings: IslandSettings
    private let model: IslandModel
    private let panel = HaloPanel()
    private let backdrop: IslandBackdrop
    private var backdropUpdatePending = false

    private let nowPlaying = NowPlayingMonitor()
    private let calendar = CalendarMonitor()
    private let wellness = WellnessMonitor()
    private let weather = WeatherMonitor()
    private let clipboard = ClipboardHistory()
    private lazy var clipboardWindow = ClipboardWindowController(history: clipboard) { [weak self] text, symbol in
        if text == "Copied" {
            self?.model.show(.success(text: text))
        } else {
            self?.model.show(.message(text: text, symbol: symbol))
        }
    }
    /// ⌃⌘V, from anywhere.
    /// ⌃⌘H opens the island, or puts it away.
    private lazy var islandHotKey = GlobalHotKey(keyCode: 4, modifiers: 4096 | 256) { [weak self] in
        self?.model.toggleFromShortcut()
    }

    private var scrollRemainder: CGFloat = 0

    /// Scrolling over the compact island changes the volume, a notch at a time.
    private func scrollVolume(_ delta: CGFloat) -> Bool {
        guard model.expanded == nil, model.transient.map({ !$0.isCard }) ?? true else { return false }
        scrollRemainder += delta
        let stepSize: CGFloat = 10
        guard abs(scrollRemainder) >= stepSize else { return true }
        let steps = (scrollRemainder / stepSize).rounded(.towardZero)
        scrollRemainder -= steps * stepSize
        guard let level = volume.adjustVolume(by: Float(steps) / 32) else { return true }
        model.updateVolume(level: level.volume, muted: level.muted)
        if settings.showVolume { model.show(.volume(level: level.volume, muted: level.muted)) }
        return true
    }

    private lazy var clipboardHotKey = GlobalHotKey(keyCode: 9, modifiers: 4096 | 256) { [weak self] in
        guard let self, self.settings.clipboardHistory else { return }
        self.clipboardWindow.toggle()
    }
    private let privacy = PrivacyMonitor()
    private let volume = VolumeMonitor()
    private let brightness = BrightnessMonitor()
    private let battery = BatteryMonitor()
    private let bluetooth = BluetoothMonitor()
    private let network = NetworkMonitor()
    private let downloads = DownloadsMonitor()
    private let mediaKeys = MediaKeyInterceptor()

    private var mouseTimer: Timer?
    private var screenFrame: CGRect = .zero
    private var capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    private var lastPowerChange = Date.distantPast
    private var announcedRain: Date?
    private var fullScreenCheckCountdown = 0
    private var accessibilityPoll: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    init(settings: IslandSettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        model = IslandModel(settings: settings, nowPlaying: nowPlaying, calendar: calendar, weather: weather,
                            privacy: privacy, clipboard: clipboard, openSettings: openSettings)

        let hosting = IslandHostingView(rootView: IslandView(model: model))
        hosting.sizingOptions = []
        hosting.onSwipe = { [weak model] step in model?.swipe(step) }
        backdrop = IslandBackdrop(content: hosting)
        panel.contentView = backdrop.root
        hosting.onVerticalScroll = { [weak self] delta in self?.scrollVolume(delta) ?? false }

        // The body follows the model on the next turn of the run loop, after SwiftUI
        // has seen the same change, so outline and content move together.
        model.objectWillChange
            .sink { [weak self] _ in self?.scheduleBackdropUpdate() }
            .store(in: &cancellables)

        wireMonitors()

        // Settings publish before the new value is stored; apply on the next turn.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Audio devices, displays and event taps can all change across sleep; start fresh.
                self?.stopMonitors()
                self?.applySettings()
            }
        })

        applySettings()
    }

    // MARK: Wiring

    private func wireMonitors() {
        volume.onChange = { [weak self] level, muted in
            guard let self else { return }
            self.model.updateVolume(level: level, muted: muted)
            guard self.settings.showVolume else { return }
            self.model.show(.volume(level: level, muted: muted))
        }
        volume.onOutputChange = { [weak self] output in
            guard let self, self.settings.showAudioOutput, output.isNotable else { return }
            self.model.show(.audioOutput(output))
        }
        brightness.onChange = { [weak self] level in
            guard let self, self.settings.showBrightness else { return }
            // macOS changes screen brightness itself when the charger goes in or out;
            // that is the charging alert's moment, not a brightness one.
            guard Date().timeIntervalSince(self.lastPowerChange) > 2.5 else { return }
            self.model.show(.brightness(level: level))
        }
        battery.onEvent = { [weak self] event in
            guard let self else { return }
            if case .lowPowerMode = event {} else { self.lastPowerChange = Date() }
            guard self.settings.showBattery else { return }
            switch event {
            case let .charging(percent): self.model.show(.charging(percent: percent))
            case let .unplugged(percent): self.model.show(.unplugged(percent: percent))
            case let .low(percent): self.model.show(.lowBattery(percent: percent))
            case let .lowPowerMode(on):
                // macOS switches Low Power Mode as the charger goes in or out ("only on
                // battery"); that moment belongs to the charging animation. Wait a beat
                // for the power change to arrive, and only then say anything.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, abs(self.lastPowerChange.timeIntervalSinceNow) > 5 else { return }
                    self.model.show(.lowPowerMode(on: on))
                }
            }
        }
        bluetooth.onConnect = { [weak self] device in
            guard let self, self.settings.showBluetooth else { return }
            self.model.show(.bluetoothConnected(device))
        }
        bluetooth.onDisconnect = { [weak self] device in
            guard let self, self.settings.showBluetooth else { return }
            self.model.show(.bluetoothDisconnected(device))
        }
        network.onEvent = { [weak self] event in
            guard let self, self.settings.showNetwork else { return }
            self.model.show(.network(event))
        }
        weather.$conditions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conditions in
                guard let self, self.settings.rainAlerts, let start = conditions?.rainStart else { return }
                let minutes = Int((start.timeIntervalSinceNow / 60).rounded())
                guard minutes <= 60, self.announcedRain != start else { return }
                self.announcedRain = start
                self.model.announce(minutes <= 1 ? "Rain starting now" : "Rain starting in \(minutes) min", symbol: "cloud.rain.fill")
            }
            .store(in: &cancellables)
        calendar.onEventStarting = { [weak self] event in
            guard let self, self.settings.showCalendar else { return }
            self.model.show(.eventStarting(title: event.title, color: event.color))
        }
        downloads.onProgress = { [weak self] progress in
            self?.model.updateDownload(progress)
        }
        downloads.onFinished = { [weak self] download in
            guard let self, self.settings.showDownloads else { return }
            self.model.show(.download(download))
        }
        clipboard.onCopy = { [weak self] item in
            guard let self, self.settings.showCopiedInIsland else { return }
            self.model.show(.copied(item))
        }
        model.openClipboard = { [weak self] in self?.clipboardWindow.show() }

        clipboard.onScreenshot = { [weak self] item in
            self?.model.show(.screenshot(item))
        }

        mediaKeys.handler = { [weak self] key, fine in
            self?.handleMediaKey(key, fineSteps: fine) ?? false
        }

        model.canStopScreenRecording = { [weak self] in self?.mediaKeys.isTrusted ?? false }
        model.stopScreenRecording = { Self.postStopRecordingShortcut() }

        settings.commandHandler = { [weak self] command, value in
            self?.handleCommand(command, value: value)
        }
    }

    /// Volume and brightness keys, when Island has taken them over from macOS.
    private func handleMediaKey(_ key: MediaKeyInterceptor.Key, fineSteps: Bool) -> Bool {
        guard settings.isEnabled, settings.replaceSystemHUD else { return false }
        let step: Float = fineSteps ? 1 / 64 : 1 / 16

        switch key {
        case .volumeUp, .volumeDown, .mute:
            let result: (volume: Float, muted: Bool)?
            switch key {
            case .volumeUp: result = volume.adjustVolume(by: step)
            case .volumeDown: result = volume.adjustVolume(by: -step)
            default: result = volume.toggleMute()
            }
            // A device without software volume (some HDMI outputs): let macOS handle it.
            guard let result else { return false }
            if settings.showVolume { model.show(.volume(level: result.volume, muted: result.muted)) }
            if key != .mute { Self.playVolumeFeedback() }
            return true

        case .brightnessUp, .brightnessDown:
            guard let level = brightness.adjust(by: key == .brightnessUp ? step : -step) else { return false }
            if settings.showBrightness { model.show(.brightness(level: level)) }
            return true
        }
    }

    /// The same "pop" macOS plays on volume change, when the user has it switched on.
    private static func playVolumeFeedback() {
        guard UserDefaults(suiteName: UserDefaults.globalDomain)?.integer(forKey: "com.apple.sound.beep.feedback") == 1 else { return }
        NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
                byReference: true)?.play()
    }

    /// Control-Command-Escape stops a macOS screen recording.
    private static func postStopRecordingShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let escape: CGKeyCode = 53
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: escape, keyDown: isDown)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }

    private func handleCommand(_ command: String, value: Bool) {
        switch command {
        case "setLaunchAtLogin":
            LoginItem.set(value)
            publishStatus()
        case "requestAccessibility":
            mediaKeys.requestAccess()
            watchForAccessibilityGrant()
        case "quit":
            NSApp.terminate(nil)
        case "showNowPlaying":
            model.expand(.nowPlaying)
        case "showControls":
            model.expand(.controls)
        case "showWeather":
            model.expand(.weather)
        case "showClipboard":
            clipboardWindow.show()
        case "showSuccess":
            model.show(.success(text: "Added to Clipboard"))
        case "showMenu":
            // Opens the Now Playing menu below the island for a look, closing itself after.
            model.expand(.nowPlaying)
            let screen = targetScreen()?.screen ?? NSScreen.main
            let point = NSPoint(x: (screen?.frame.midX ?? 700) + 180, y: (screen?.frame.maxY ?? 900) - 70)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                MusicMenu.present(model: self.model, at: point, autoDismissAfter: 4)
            }
        case "showPage.timer": model.expand(.timer)
        case "showPage.lyrics": model.expand(.lyrics)
        case "showPage.shortcuts": model.expand(.shortcuts)
        case "showPage.system": model.expand(.system)
        case "showPage.reminders": model.expand(.reminders)
        case "showPage.notes": model.expand(.notes)
        case "showPage.mirror": model.expand(.mirror)
        case "showCharging":
            let snapshot = battery.snapshot()
            model.show(.charging(percent: snapshot?.percent ?? 80))
        case "showUnplugged":
            model.show(.unplugged(percent: battery.snapshot()?.percent ?? 80))
        case "demo.capsLock": model.show(.capsLock(on: true))
        case "demo.lowPower": model.show(.lowPowerMode(on: true))
        case "demo.lowBattery": model.show(.lowBattery(percent: 12))
        case "demo.airpods":
            model.show(.bluetoothConnected(BluetoothDeviceInfo(name: "AirPods Pro", symbol: "airpodspro",
                                                               batteryLeft: 84, batteryRight: 80, batterySingle: nil)))
        case "demo.network": model.show(.network(.wifi))
        case "demo.message": model.show(.message(text: "Take a 5-minute break", symbol: "cup.and.saucer.fill"))
        case "demo.download":
            // A 4-second download of a 1.2 GB file, for the promo.
            let total: Int64 = 1_240_000_000
            for step in 0...16 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.25) { [weak self] in
                    let bytes = total * Int64(step) / 16
                    self?.model.updateDownload(step == 16 ? nil : DownloadProgress(name: "Final Cut Project.zip", bytes: bytes, total: total,
                                                                                    bytesPerSecond: 38_000_000, others: 0))
                    if step == 16 {
                        let file = ImageTools.outputFolder.appendingPathComponent("Final Cut Project.zip")
                        if !FileManager.default.fileExists(atPath: file.path) {
                            FileManager.default.createFile(atPath: file.path, contents: Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)))
                        }
                        self?.model.show(.download(DownloadInfo(url: file, isAirDrop: false)))
                    }
                }
            }
        case "demo.rain": model.announce("Rain starting in 15 min", symbol: "cloud.rain.fill")
        case "demo.eventStarting": model.show(.eventStarting(title: "Design Review", color: .red))
        case "demo.siri": SiriMonitor.activate()
        case "demo.siriClose":
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?.activate()
        case "demo.collapse":
            model.dismissTransient()
            model.collapse()
        case "demo.pomodoro":
            model.timer.startPomodoro()
            model.expand(.timer)
        case "demo.stopTimer": model.timer.stop()
        case "demo.closeClipboard": clipboardWindow.close()
        case "demo.clearClipboard": clipboard.clearUnpinned()
        case "demo.unplugged": model.show(.unplugged(percent: battery.snapshot()?.percent ?? 80))
        case "demo.smartDrop":
            let url = URL(fileURLWithPath: "/Library/User Pictures/Animals/Parrot.heic")
            if let item = clipboard.add(fileURL: url, source: "Demo") { model.dropped(item) }
        case "demo.smartDropQR":
            // Halo's own folder, not ~/Documents — that needs a TCC prompt Halo has
            // never been granted, which is exactly what tripped this up the first time.
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Halo/Demo/qr-demo.png")
            if let item = clipboard.add(fileURL: url, source: "Demo") { model.dropped(item) }
        case "demo.removeBackground": model.removeDroppedBackground()
        case "demo.copyText": model.copyDroppedText()
        case "demo.readQR": model.readDroppedQRCode()
        case "demo.copyPhone":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Call me at +1 (415) 555-2671 about the shoot", forType: .string)
        case "demo.copyAddress":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("1 Infinite Loop, Cupertino, CA 95014", forType: .string)
        case "timer.test": model.timer.startCountdown(minutes: 0.15)
        case "timer.stop": model.timer.stop()
        case "editNote": model.editNote()
        case "closeEditor": QuickEditor.shared.close(returnFocus: true)
        default:
            break
        }
    }

    func publishStatus() {
        settings.updateStatus(launchAtLogin: LoginItem.isEnabled, accessibilityGranted: mediaKeys.isTrusted)
    }

    /// Accessibility has no change notification; check for a while after asking.
    private func watchForAccessibilityGrant() {
        accessibilityPoll?.invalidate()
        var checks = 0
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                checks += 1
                if self.mediaKeys.isTrusted || checks > 180 {
                    timer.invalidate()
                    self.applySettings()
                }
            }
        }
    }

    // MARK: IslandSettings

    private func applySettings() {
        publishStatus()
        guard settings.isEnabled, let target = targetScreen() else {
            stopMonitors()
            stopWatchingMenuBar()
            model.reset()
            panel.orderOut(nil)
            stopMouseTracking()
            return
        }

        toggle(nowPlaying.start, nowPlaying.stop, settings.showNowPlaying)
        toggle(volume.start, volume.stop, settings.showVolume || settings.showAudioOutput || settings.replaceSystemHUD)
        toggle(brightness.start, brightness.stop, settings.showBrightness)
        toggle(battery.start, battery.stop, settings.showBattery)
        toggle(bluetooth.start, bluetooth.stop, settings.showBluetooth)
        toggle(privacy.start, privacy.stop, settings.showPrivacy || settings.showCalls)
        toggle(calendar.start, calendar.stop, settings.showCalendar)
        toggle(model.siri.start, model.siri.stop, settings.showSiri)
        wellness.update(eyeBreaks: settings.eyeBreaks, water: settings.hydrationReminders)
        toggle(weather.start, weather.stop, settings.usesWeather)
        toggle(clipboard.start, clipboard.stop, settings.clipboardHistory)
        clipboard.copiesScreenshots = settings.copyScreenshots
        if !islandHotKey.register() { islandLog.error("couldn't register ⌃⌘H") }
        ScreenshotLocation.apply(keepOffDesktop: settings.clipboardHistory && settings.screenshotsOffDesktop)
        if settings.clipboardHistory {
            if !clipboardHotKey.register() { islandLog.error("couldn't register ⌃⌘V") }
        } else {
            clipboardHotKey.unregister()
        }
        if settings.usesWeather { weather.updateCity(settings.weatherCity) }
        toggle(network.start, network.stop, settings.showNetwork)
        toggle(downloads.start, downloads.stop, settings.showDownloads)
        if settings.replaceSystemHUD {
            if !mediaKeys.start() { mediaKeys.stop() }
        } else {
            mediaKeys.stop()
        }

        model.updateNotch(size: target.notch, hasNotch: target.hasNotch)
        position(on: target.screen)
        watchMenuBar(on: target.screen, notch: target.notch)
        model.batterySnapshot = { [weak self] in self?.battery.snapshot() }
        model.outputVolume = { [weak self] in self?.volume.currentLevel() }
        model.setOutputVolume = { [weak self] level in
            self?.volume.setVolume(level)
            self?.model.updateVolume(level: level, muted: level == 0)
        }
        model.screenFrame = { [weak self] in self?.screenFrame ?? NSScreen.main?.frame ?? .zero }
        wellness.onReminder = { [weak self] reminder in
            guard let self, !self.model.isFullScreen else { return }
            switch reminder {
            case .eyeBreak: self.model.announce("Look 20 feet away for 20 seconds", symbol: "eye.fill")
            case .water: self.model.announce("Time for a glass of water", symbol: "drop.fill")
            }
        }
        model.toggleMute = { [weak self] in
            guard let self, let level = self.volume.toggleMute() else { return }
            self.model.updateVolume(level: level.volume, muted: level.muted)
        }
        model.refreshVolume()
        trackFullScreen()
        if !panel.isVisible, !model.isFullScreen { panel.orderFrontRegardless() }
        startMouseTracking()
    }

    // MARK: Menu bar

    private var menuBarTimer: Timer?
    private var menuBarObserver: NSObjectProtocol?

    /// Keeps the model told how much room there is beside the notch. Menu bar icons
    /// come and go, and each app has its own menus, so this is measured every couple of
    /// seconds and whenever another app comes forward.
    private func watchMenuBar(on screen: NSScreen, notch: CGSize) {
        let measure = { [weak self] in
            guard let self else { return }
            self.model.updateMenuBarRoom(Self.menuBarRoom(on: screen, notch: notch))
        }
        measure()
        menuBarTimer?.invalidate()
        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { measure() }
        }
        if let menuBarObserver { NSWorkspace.shared.notificationCenter.removeObserver(menuBarObserver) }
        menuBarObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            // The new app's menus are laid out a moment after it activates.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { measure() } }
        }
    }

    private func stopWatchingMenuBar() {
        menuBarTimer?.invalidate()
        menuBarTimer = nil
        if let menuBarObserver { NSWorkspace.shared.notificationCenter.removeObserver(menuBarObserver) }
        menuBarObserver = nil
    }

    /// The gap between the notch and the nearest menu bar item on either side, less a
    /// little breathing room. Status icons are windows at the status level along the top
    /// of the screen; the frontmost app's menus come from Accessibility, when allowed.
    static func menuBarRoom(on screen: NSScreen, notch: CGSize) -> IslandModel.MenuBarRoom {
        let notchLeft = screen.frame.midX - notch.width / 2
        let notchRight = screen.frame.midX + notch.width / 2
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let top = primaryHeight - screen.frame.maxY
        var left = CGFloat.greatestFiniteMagnitude
        var right = CGFloat.greatestFiniteMagnitude
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  window[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"],
                  abs(y - top) < 4, width < 400 else { continue }
            if x >= notchRight - 2 {
                right = min(right, x - notchRight)
            } else if x + width <= notchLeft + 2 {
                left = min(left, notchLeft - (x + width))
            }
        }

        if !AXIsProcessTrusted() {
            // Without Accessibility the app's menus can't be measured; the island stays
            // symmetric, as wide as the room on the right allows.
        } else if let app = NSWorkspace.shared.frontmostApplication {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var menuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBar) == .success,
               let menuBar, CFGetTypeID(menuBar) == AXUIElementGetTypeID() {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                   let items = children as? [AXUIElement] {
                    for item in items {
                        guard let frame = axFrame(item), abs(frame.minY - top) < 4, frame.width > 0 else { continue }
                        if frame.maxX <= notchLeft + 2 {
                            left = min(left, notchLeft - frame.maxX)
                        }
                    }
                }
            }
        }
        // Status icons sit inside their windows with padding of their own, so the window edge is the limit.
        return IslandModel.MenuBarRoom(left: max(0, left - 4), right: max(0, right))
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    private func toggle(_ start: () -> Void, _ stop: () -> Void, _ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func stopMonitors() {
        nowPlaying.stop()
        volume.stop()
        brightness.stop()
        battery.stop()
        bluetooth.stop()
        privacy.stop()
        calendar.stop()
        wellness.update(eyeBreaks: false, water: false)
        weather.stop()
        clipboard.stop()
        clipboardHotKey.unregister()
        islandHotKey.unregister()
        network.stop()
        downloads.stop()
        mediaKeys.stop()
    }

    // MARK: Placement

    private func targetScreen() -> (screen: NSScreen, notch: CGSize, hasNotch: Bool)? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = left > 0 && right > 0 ? screen.frame.width - left - right : 185
            return (screen, CGSize(width: width.rounded(), height: screen.safeAreaInsets.top), true)
        }
        guard settings.showOnDisplaysWithoutNotch, let screen = NSScreen.screens.first else { return nil }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return (screen, CGSize(width: 190, height: menuBar > 20 ? menuBar : 28), false)
    }

    private func position(on screen: NSScreen) {
        let extent = model.maximumExtent
        let shadowRoom: CGFloat = 44
        let size = CGSize(width: extent.width + shadowRoom * 2, height: extent.height + shadowRoom)
        let frame = CGRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        screenFrame = screen.frame
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        scheduleBackdropUpdate()
    }

    // MARK: Island body

    private func scheduleBackdropUpdate() {
        guard !backdropUpdatePending else { return }
        backdropUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backdropUpdatePending = false
            self.updateBackdrop()
        }
    }

    private func updateBackdrop() {
        let bounds = backdrop.root.bounds
        guard bounds.width > 0 else { return }
        let layout = model.layout

        // Pressing squeezes the island; hovering over a compact activity lifts it a touch.
        var scale: CGFloat = 1
        if model.isPressed {
            scale = 0.95
        } else if model.isHovering, case .compact = model.presentation {
            scale = 1.035
        }
        let size = CGSize(width: layout.size.width * scale, height: layout.size.height * scale)
        let centre = bounds.midX + layout.offsetX
        let rect = CGRect(x: (centre - size.width / 2).rounded(), y: 0, width: size.width, height: size.height)

        let bubble = layout.bubbleDiameter.map { diameter in
            CGRect(x: centre + layout.size.width / 2 + IslandLayout.bubbleGap, y: 0, width: diameter, height: diameter)
        }

        backdrop.apply(IslandBackdrop.State(
            rect: rect, topRadius: layout.topRadius, bottomRadius: layout.bottomRadius * scale,
            bubble: bubble, isCard: layout.isCard, usesGlass: settings.liquidGlass,
            isVisible: layout.isVisible, notchHeight: model.notchSize.height
        ))
    }

    // MARK: Pointer and keyboard state

    /// The window is larger than the island, so it lets clicks through everywhere
    /// except over the island itself. Polling the pointer is what makes that
    /// possible — a window ignoring the mouse gets no hover events to react to.
    private var clickOutsideMonitor: Any?

    private func startMouseTracking() {
        if clickOutsideMonitor == nil {
            // Clicks in other apps' windows (Island's own windows never reach a global
            // monitor, and it needs no permission for mouse clicks).
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickedOutside() }
            }
        }
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        clickOutsideMonitor = nil
    }

    /// Clicking back into another window puts the island away straight away, even during
    /// the few seconds it otherwise stays open.
    private func clickedOutside() {
        guard model.expanded != nil, !model.isMenuOpen, !model.isDraggingOut else { return }
        let size = model.layout.size
        let centre = screenFrame.midX + model.layout.offsetX
        let island = CGRect(x: centre - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
        guard !island.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
        model.collapse()
    }

    private func tick() {
        trackMouse()
        trackCapsLock()

        // Checking every frame would be wasteful; twice a second is plenty.
        fullScreenCheckCountdown -= 1
        if fullScreenCheckCountdown <= 0 {
            fullScreenCheckCountdown = 15
            trackFullScreen()
        }
    }

    private func trackFullScreen() {
        guard let screen = targetScreen()?.screen else { return }
        let fullScreen = settings.hideInFullScreen && FullScreenMonitor.isFullScreen(on: screen)
        guard fullScreen != model.isFullScreen else { return }
        islandLog.notice("full screen \(fullScreen, privacy: .public)")
        model.setFullScreen(fullScreen)
        if fullScreen {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func trackCapsLock() {
        // Read from the event system's state, which needs no permission.
        let on = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        guard on != capsLockOn else { return }
        capsLockOn = on
        if settings.showCapsLock { model.show(.capsLock(on: on)) }
    }

    private func trackMouse() {
        let point = NSEvent.mouseLocation
        let layout = model.layout
        let size = layout.size
        let top = screenFrame.maxY

        if model.isDraggingOut, NSEvent.pressedMouseButtons == 0 {
            model.isDraggingOut = false
            model.scheduleCollapseIfNeeded()
        }

        var inside = false
        let centre = screenFrame.midX + layout.offsetX
        let island = CGRect(x: centre - size.width / 2, y: top - size.height,
                            width: size.width, height: size.height + 1)
        if island.insetBy(dx: -4, dy: -4).contains(point) { inside = true }

        if let diameter = layout.bubbleDiameter {
            let bubble = CGRect(x: centre + size.width / 2 + IslandLayout.bubbleGap, y: top - diameter,
                                width: diameter, height: diameter + 1)
            if bubble.insetBy(dx: -3, dy: -3).contains(point) { inside = true }
        }

        // An idle island on a display without a notch is invisible, so only the
        // menu bar strip directly above where it would appear wakes it.
        if !layout.isVisible && !model.isHovering {
            inside = island.contains(point) && point.y >= top - model.notchSize.height
        }

        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }
}
