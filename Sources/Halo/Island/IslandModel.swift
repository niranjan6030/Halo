import AppKit
import Combine
import HaloCore
import OSLog
import SwiftUI

let islandLog = Logger(subsystem: "com.niranjan.Halo", category: "island")

/// Ongoing things the island shows in compact form, most important first.
enum Activity: Hashable, CaseIterable {
    case call
    case screenRecording
    case recording
    /// A browser download still arriving.
    case download
    case nowPlaying
    case timer
    case calendar
    case privacy
}

enum ExpandedContent: Hashable {
    case call
    case screenRecording
    case recording
    case nowPlaying
    case calendar
    /// Battery, volume and quick actions — what the island shows when nothing is live.
    case controls
    case weather
    case lyrics
    case timer
    case system
    case reminders
    case notes
    case shortcuts
    case mirror
    /// Tools for an image just dropped on the island.
    case smartDrop
}

/// Short-lived alerts that take over the island for a moment, then hand it back.
enum TransientEvent: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case charging(percent: Int)
    case unplugged(percent: Int)
    case lowBattery(percent: Int)
    case lowPowerMode(on: Bool)
    case bluetoothConnected(BluetoothDeviceInfo)
    case bluetoothDisconnected(BluetoothDeviceInfo)
    case audioOutput(AudioOutputInfo)
    case network(NetworkMonitor.Event)
    case capsLock(on: Bool)
    case download(DownloadInfo)
    case screenshot(ClipboardItem)
    /// Something is being dragged over the island.
    case dropTarget
    /// Short feedback after an action ("Added to Pop Pop", "Couldn't add").
    case message(text: String, symbol: String)
    /// Something was just copied; clicking it opens the clipboard.
    case copied(ClipboardItem)
    /// An action finished: shown with the Face ID-style checkmark.
    case success(text: String)
    /// A marked calendar event's start time just arrived.
    case eventStarting(title: String, color: Color)

    /// Updates of the same kind (volume 40% → 45%) keep the view in place and just
    /// animate the value, instead of cross-fading a new view in.
    var kind: String {
        switch self {
        case .volume: return "volume"
        case .brightness: return "brightness"
        case .charging: return "charging"
        case .unplugged: return "unplugged"
        case .lowBattery: return "lowBattery"
        case .lowPowerMode: return "lowPowerMode"
        case .bluetoothConnected: return "bluetoothConnected"
        case .bluetoothDisconnected: return "bluetoothDisconnected"
        case .audioOutput: return "audioOutput"
        case .network: return "network"
        case .capsLock: return "capsLock"
        case .download: return "download"
        case .screenshot: return "screenshot"
        case .dropTarget: return "dropTarget"
        case .message: return "message"
        case .copied: return "copied"
        case .success: return "success"
        case .eventStarting: return "eventStarting"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .capsLock: return 1.6
        case .charging: return 3
        case .bluetoothConnected, .audioOutput, .network, .lowPowerMode: return 3
        case .unplugged, .bluetoothDisconnected: return 2.2
        case .download, .lowBattery: return 5
        case .screenshot: return 6
        case .dropTarget: return 30
        case .message: return 2
        case .copied: return 1.6
        case .success: return 2.2
        case .eventStarting: return 6
        }
    }

    /// Alerts are cards with buttons below the notch; the rest are strips around it.
    var isCard: Bool {
        switch self {
        case .screenshot, .dropTarget: return true
        default: return false
        }
    }

    /// Alerts that must not be replaced by a passing volume change.
    var isImportant: Bool {
        switch self {
        case .lowBattery: return true
        default: return false
        }
    }
}

enum Presentation: Equatable {
    case idle
    case compact(Activity, minimal: Activity?)
    case transient(TransientEvent)
    case expanded(ExpandedContent, minimal: Activity?)

    var contentID: String {
        switch self {
        case .idle: return "idle"
        case let .compact(activity, _): return "compact.\(activity)"
        case let .transient(event): return "transient.\(event.kind)"
        case let .expanded(content, _): return "expanded.\(content)"
        }
    }

    var minimal: Activity? {
        switch self {
        case let .compact(_, minimal), let .expanded(_, minimal): return minimal
        default: return nil
        }
    }
}

struct IslandLayout: Equatable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var bubbleDiameter: CGFloat?
    var isVisible: Bool
    /// How far the island's centre sits right of the notch's (negative: left), for a
    /// compact activity that grows only one way.
    var offsetX: CGFloat = 0
    /// Expanded views and alert cards: drawn with Liquid Glass and a shadow.
    var isCard: Bool

    static let bubbleGap: CGFloat = 6
}

@MainActor
final class IslandModel: ObservableObject {
    let settings: IslandSettings
    let nowPlaying: NowPlayingMonitor
    let calendar: CalendarMonitor
    let weather: WeatherMonitor
    let focus = FocusController()
    let toggles = SystemToggles()
    @Published private(set) var isTestingSpeed = false
    @Published private(set) var downloadProgress: DownloadProgress?

    func updateDownload(_ progress: DownloadProgress?) {
        if downloadProgress != progress { downloadProgress = progress }
    }

    // MARK: Smart Drop

    @Published private(set) var dropItem: ClipboardItem?
    @Published private(set) var dropBusy = false
    @Published private(set) var dropStatus: String?

    /// Something landed on the island: images get the Smart Drop tools, anything else
    /// is simply kept in the clipboard.
    func dropped(_ item: ClipboardItem) {
        dismissTransient()
        if case .image = item.content {
            dropItem = item
            dropStatus = nil
            expand(.smartDrop)
        } else {
            show(.success(text: "Added to Clipboard"))
        }
    }

    private var droppedImage: (image: NSImage, file: URL)? {
        guard let dropItem, case let .image(image, file) = dropItem.content else { return nil }
        return (image, file)
    }

    func removeDroppedBackground() {
        guard let dropped = droppedImage, !dropBusy else { return }
        dropBusy = true
        dropStatus = "Finding the subject…"
        Task { [weak self] in
            let cutout = await ImageTools.removeBackground(from: dropped.image)
            guard let self else { return }
            self.dropBusy = false
            guard let cutout,
                  let url = ImageTools.save(cutout, as: .png, named: dropped.file.deletingPathExtension().lastPathComponent + " cutout") else {
                self.dropStatus = "Couldn't find a subject to lift out"
                return
            }
            self.keepMade(cutout, at: url, status: "Background removed · copied")
        }
    }

    func copyDroppedText() {
        guard let dropped = droppedImage, !dropBusy else { return }
        dropBusy = true
        dropStatus = "Reading the text…"
        Task { [weak self] in
            let text = await ImageTools.recognizeText(in: dropped.image)
            guard let self else { return }
            self.dropBusy = false
            guard let text else {
                self.dropStatus = "No text in this image"
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let lines = text.split(separator: "\n").count
            self.dropStatus = "Copied \(lines) line\(lines == 1 ? "" : "s") of text"
            self.haptic(.levelChange)
        }
    }

    func readDroppedQRCode() {
        guard let dropped = droppedImage, !dropBusy else { return }
        dropBusy = true
        dropStatus = "Looking for a code…"
        Task { [weak self] in
            let payload = await ImageTools.readQRCode(in: dropped.image)
            guard let self else { return }
            self.dropBusy = false
            guard let payload, !payload.isEmpty else {
                self.dropStatus = "No QR code found in this image"
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(payload, forType: .string)
            self.haptic(.levelChange)
            if let url = URL(string: payload), let scheme = url.scheme, scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                self.dropStatus = "Copied and opened the link"
            } else {
                let shown = payload.count > 60 ? String(payload.prefix(60)) + "…" : payload
                self.dropStatus = "Copied: \(shown)"
            }
        }
    }

    func convertDropped(to format: ImageTools.Format) {
        guard let dropped = droppedImage, !dropBusy else { return }
        guard let url = ImageTools.save(dropped.image, as: format, named: dropped.file.deletingPathExtension().lastPathComponent) else {
            dropStatus = "Couldn't convert it"
            return
        }
        keepMade(dropped.image, at: url, status: "Saved as \(format.fileExtension.uppercased()) · copied")
    }

    private func keepMade(_ image: NSImage, at url: URL, status: String) {
        if let item = clipboard.add(fileURL: url, source: "Smart Drop") {
            withAnimation(.smooth(duration: 0.3)) { dropItem = item }
        }
        ImageTools.copy(image: image, file: url)
        clipboard.ignoreCurrentPasteboard()
        dropStatus = status
        haptic(.levelChange)
    }
    let timer = TimerController()
    let stats = SystemStats()
    let fps = FPSMeter()
    let lyrics = LyricsMonitor()
    let shortcuts = ShortcutsLibrary()
    let reminders = RemindersMonitor()
    let privacy: PrivacyMonitor
    let clipboard: ClipboardHistory
    let openSettings: () -> Void

    /// Set by the controller: sends the stop-recording shortcut when possible.
    var stopScreenRecording: (() -> Void)?
    var canStopScreenRecording: () -> Bool = { false }

    @Published private(set) var expanded: ExpandedContent?
    /// +1 or -1 while moving between pages (they slide), 0 otherwise (content fades in).
    private(set) var pageStep = 0
    @Published private(set) var transient: TransientEvent?
    @Published private(set) var isHovering = false
    @Published private(set) var isDropTargeted = false
    /// The three-dot menu is open; the island must stay put behind it.
    @Published private(set) var isMenuOpen = false

    /// A press is in progress on the compact island (it squeezes, as on iPhone).
    @Published private(set) var isPressed = false
    /// An app is full screen on this display; the island stays out of the way.
    @Published private(set) var isFullScreen = false

    /// The system output level, kept current so the island's slider never lags.
    @Published private(set) var volumeLevel: Float = 0.5
    @Published private(set) var volumeMuted = false

    /// Supplied by the controller, which owns the system monitors.
    var batterySnapshot: () -> BatteryMonitor.Snapshot? = { nil }
    var outputVolume: () -> (volume: Float, muted: Bool)? = { nil }
    var setOutputVolume: (Float) -> Void = { _ in }
    var toggleMute: () -> Void = {}
    var openClipboard: () -> Void = {}

    /// Called by the controller whenever the output level changes, and by the slider.
    func updateVolume(level: Float, muted: Bool) {
        if abs(volumeLevel - level) > 0.001 { volumeLevel = level }
        if volumeMuted != muted { volumeMuted = muted }
    }

    func refreshVolume() {
        guard let output = outputVolume() else { return }
        updateVolume(level: output.volume, muted: output.muted)
    }
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasNotch = true
    /// Activities swiped away. Each comes back when it has something new to show.
    @Published private(set) var dismissed: Set<Activity> = []

    /// While a file is being dragged out of the island, it must not collapse under the pointer.
    var isDraggingOut = false

    private var transientWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var hoverExpandWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: IslandSettings, nowPlaying: NowPlayingMonitor, calendar: CalendarMonitor,
         weather: WeatherMonitor, privacy: PrivacyMonitor, clipboard: ClipboardHistory,
         openSettings: @escaping () -> Void) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.calendar = calendar
        self.weather = weather
        self.privacy = privacy
        self.clipboard = clipboard
        self.openSettings = openSettings

        let publishers: [ObservableObjectPublisher] = [settings.objectWillChange, nowPlaying.objectWillChange, calendar.objectWillChange,
                                                        weather.objectWillChange, privacy.objectWillChange,
                                                        clipboard.objectWillChange, focus.objectWillChange, toggles.objectWillChange,
                                                        timer.objectWillChange, stats.objectWillChange, fps.objectWillChange, reminders.objectWillChange,
                                                        lyrics.objectWillChange, shortcuts.objectWillChange]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
        observeContent()
        timer.onFinish = { [weak self] message, symbol in
            guard let self else { return }
            if self.settings.timerSound { NSSound(named: "Glass")?.play() }
            self.announce(message, symbol: symbol)
        }
    }

    /// The screen the island is on, for placing windows under it.
    var screenFrame: () -> CGRect = { NSScreen.main?.frame ?? .zero }

    private var belowNotch: CGRect {
        let frame = screenFrame()
        return CGRect(x: frame.midX - 1, y: frame.maxY - notchSize.height, width: 2, height: 1)
    }

    func editNote() {
        collapse()
        QuickEditor.shared.editNote(below: belowNotch)
    }

    func editReminder() {
        collapse()
        QuickEditor.shared.addReminder(below: belowNotch) { [weak self] title in
            guard let self, self.reminders.add(title) else { return false }
            self.show(.success(text: "Reminder added"))
            return true
        }
    }

    /// Something the user asked to be told about (a timer ending, a reminder to rest):
    /// shown even if the island is open, unless the pointer is on it.
    func announce(_ text: String, symbol: String) {
        if expanded != nil {
            guard !isHovering, !isMenuOpen else {
                haptic(.levelChange)
                return
            }
            collapse()
        }
        show(.message(text: text, symbol: symbol))
    }

    /// Closes views whose content has gone, and brings swiped-away activities back
    /// when something new happens in them.
    private func observeContent() {
        var lastTitle: String?
        var wasPlaying = false
        nowPlaying.$track
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if track?.title != lastTitle || (track?.isPlaying == true && !wasPlaying) {
                    self.undismiss(.nowPlaying)
                }
                lastTitle = track?.title
                wasPlaying = track?.isPlaying == true
                if track == nil, self.expanded == .nowPlaying { self.collapse() }
            }
            .store(in: &cancellables)

        calendar.$next
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.undismiss(.calendar)
                if event == nil, self.expanded == .calendar { self.collapse() }
            }
            .store(in: &cancellables)

        privacy.$call
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in
                guard let self, call == nil else { return }
                self.undismiss(.call)
                if self.expanded == .call { self.collapse() }
            }
            .store(in: &cancellables)

        privacy.$recording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                guard let self, recording == nil else { return }
                self.undismiss(.recording)
                if self.expanded == .recording { self.collapse() }
            }
            .store(in: &cancellables)

        privacy.$screenRecordingSince
            .receive(on: DispatchQueue.main)
            .sink { [weak self] since in
                guard let self, since == nil else { return }
                self.undismiss(.screenRecording)
                if self.expanded == .screenRecording { self.collapse() }
            }
            .store(in: &cancellables)

        timer.$kind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] kind in
                guard let self else { return }
                self.undismiss(.timer)
                if kind == nil, self.expanded == .timer, !self.settings.isPageOn(.timer) { self.collapse() }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(privacy.$cameraInUse, privacy.$microphoneInUse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.undismiss(.privacy) }
            .store(in: &cancellables)
    }

    private func undismiss(_ activity: Activity) {
        if dismissed.contains(activity) { dismissed.remove(activity) }
    }

    func updateNotch(size: CGSize, hasNotch: Bool) {
        if notchSize != size { notchSize = size }
        if self.hasNotch != hasNotch { self.hasNotch = hasNotch }
    }

    // MARK: What to show

    func isRunning(_ activity: Activity) -> Bool {
        switch activity {
        case .call: return settings.showCalls && privacy.call != nil
        case .screenRecording: return settings.showCalls && privacy.screenRecordingSince != nil
        case .recording: return settings.showCalls && privacy.recording != nil
        case .nowPlaying: return settings.showNowPlaying && nowPlaying.isVisible && nowPlaying.track != nil
        case .calendar: return settings.showCalendar && calendar.next != nil
        case .timer: return timer.isActive
        case .download: return settings.showDownloads && downloadProgress != nil
        case .privacy:
            // A call or recording already accounts for the microphone.
            return settings.showPrivacy && privacy.isActive && privacy.call == nil && privacy.recording == nil
        }
    }

    var activities: [Activity] {
        Activity.allCases.filter { isRunning($0) && !dismissed.contains($0) }
    }

    var presentation: Presentation {
        let current = activities
        if let expanded {
            let minimal = current.first { content(for: $0) != expanded && $0 != .privacy }
            return .expanded(expanded, minimal: minimal)
        }
        if let transient { return .transient(transient) }
        guard let primary = current.first else { return .idle }
        let minimal = current.dropFirst().first { $0 != .privacy }
        return .compact(primary, minimal: minimal)
    }

    var compactSide: CGFloat { notchSize.height + 26 }

    /// How far the island can reach past the notch on each side before it covers a
    /// menu bar icon (right) or an app's menus (left). Measured by the controller.
    struct MenuBarRoom: Equatable {
        var left: CGFloat
        var right: CGFloat
        static let unlimited = MenuBarRoom(left: .greatestFiniteMagnitude, right: .greatestFiniteMagnitude)
    }

    @Published private(set) var menuBarRoom = MenuBarRoom.unlimited

    func updateMenuBarRoom(_ room: MenuBarRoom) {
        let rounded = MenuBarRoom(left: room.left.rounded(.down), right: room.right.rounded(.down))
        if menuBarRoom != rounded { menuBarRoom = rounded }
    }

    /// The narrowest a compact activity can be and still show its icon.
    static let minimumSide: CGFloat = 30

    /// How far a compact activity reaches past the notch on the left and on the right.
    /// Normally the same both ways; when one side is full (an app's menus run up to the
    /// notch), the island grows only toward the other side and puts everything there.
    func extents(for activity: Activity) -> (left: CGFloat, right: CGFloat) {
        let wanted: CGFloat
        switch activity {
        case .call, .recording, .screenRecording, .calendar: wanted = notchSize.height + 42
        case .nowPlaying: wanted = compactSide
        case .timer: wanted = notchSize.height + 30
        case .download: wanted = notchSize.height + 36
        case .privacy: wanted = 24
        }
        guard settings.avoidMenuBarIcons else { return (wanted, wanted) }
        let room = menuBarRoom
        let both = min(wanted, room.left, room.right)
        if both >= min(wanted, Self.minimumSide) { return (both, both) }
        // Both halves of the content side by side, in whatever room there is.
        let oneSide = max(Self.minimumSide, min(wanted * 1.6, max(room.left, room.right)))
        return room.right >= room.left ? (0, oneSide) : (oneSide, 0)
    }

    var hasResumableTrack: Bool {
        settings.showNowPlaying && nowPlaying.track != nil && !isRunning(.nowPlaying)
    }

    var layout: IslandLayout {
        let notchWidth = notchSize.width
        let height = notchSize.height
        let presentation = presentation

        func strip(side: CGFloat) -> IslandLayout {
            strip(left: side, right: side)
        }

        func strip(left: CGFloat, right: CGFloat) -> IslandLayout {
            var layout = IslandLayout(size: CGSize(width: notchWidth + left + right, height: height),
                                      topRadius: 6, bottomRadius: height * 0.42, bubbleDiameter: nil,
                                      isVisible: true, isCard: false)
            layout.offsetX = (right - left) / 2
            return layout
        }

        func card(width: CGFloat, extra: CGFloat) -> IslandLayout {
            IslandLayout(size: CGSize(width: max(width, notchWidth + 80), height: height + extra),
                         topRadius: 12, bottomRadius: 38, bubbleDiameter: nil,
                         isVisible: true, isCard: true)
        }

        var result: IslandLayout
        switch presentation {
        case .idle:
            let grow: CGFloat = isHovering ? 1 : 0
            result = IslandLayout(size: CGSize(width: notchWidth + 14 * grow, height: height + 4 * grow),
                                  topRadius: hasNotch && !isHovering ? 0 : 6, bottomRadius: height * 0.34,
                                  bubbleDiameter: nil, isVisible: hasNotch || isHovering, isCard: false)

        case let .compact(activity, _):
            let extents = extents(for: activity)
            result = strip(left: extents.left, right: extents.right)

        case let .transient(event):
            switch event {
            case .volume, .brightness: result = strip(side: 78)
            case .capsLock: result = strip(side: 102)
            case .charging, .unplugged: result = strip(side: 96)
            case .lowPowerMode, .network, .lowBattery: result = strip(side: 108)
            case .bluetoothConnected, .bluetoothDisconnected: result = strip(side: 120)
            case .audioOutput, .download: result = strip(side: 112)
            case .dropTarget: result = strip(side: 112)
            case .message: result = strip(side: 128)
            case .copied: result = strip(side: 84)
            case let .success(text):
                // The message varies a lot in length ("Trash emptied" vs. "Caches are
                // already tidy" vs. "Force quit 3 apps") — a fixed width truncated the
                // longer ones. The text renders in CompactStrip's trailing region, which
                // gets exactly `side` points with 4pt of trailing padding inside it, so
                // side needs to cover the measured text width plus that padding.
                let textWidth = (text as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular)
                ]).width
                result = strip(side: max(84, ceil(textWidth) + 10))
            case let .eventStarting(title, _):
                let textWidth = (title as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]).width
                result = strip(side: max(104, ceil(textWidth) + 34))
            case .screenshot: result = strip(side: 116)
            }

        case let .expanded(content, _):
            switch content {
            case .nowPlaying: result = card(width: 460, extra: 166 + navigationRoom(for: .nowPlaying))
            case .call, .recording, .screenRecording: result = card(width: 420, extra: 100)
            case .calendar: result = card(width: 440, extra: 112 + navigationRoom(for: .calendar))
            case .controls: result = card(width: 440, extra: controlsHeight + navigationRoom(for: .controls))
            case .weather: result = card(width: 460, extra: 232 + navigationRoom(for: .weather))
            case .lyrics: result = card(width: 460, extra: 172 + navigationRoom(for: .lyrics))
            case .shortcuts: result = card(width: 440, extra: 196 + navigationRoom(for: .shortcuts))
            case .timer: result = card(width: 440, extra: (timer.isActive ? 164 : 146) + navigationRoom(for: .timer))
            case .system: result = card(width: 440, extra: 192 + navigationRoom(for: .system))
            case .reminders: result = card(width: 440, extra: 232 + navigationRoom(for: .reminders))
            case .notes: result = card(width: 440, extra: 170 + navigationRoom(for: .notes))
            case .smartDrop: result = card(width: 480, extra: 168)
            case .mirror: result = card(width: 440, extra: 250 + navigationRoom(for: .mirror))
            }
        }

        if presentation.minimal != nil {
            result.bubbleDiameter = height
        }
        return result
    }

    static let navigationHeight: CGFloat = 34

    // MARK: Controls page

    static let controlButtonSize: CGFloat = 42

    var controlTiles: [ControlTileKind] {
        [settings.leftTile, settings.rightTile].filter { $0 != .none }
    }

    static let buttonsPerRow = 6

    /// The chosen buttons, leaving out ones that can't work right now.
    var controlButtons: [ControlAction] {
        settings.buttons.filter { action in
            switch action {
            case .clipboard: return settings.clipboardHistory
            case .nightShift: return toggles.canUseNightShift
            default: return true
            }
        }
    }

    /// The buttons in rows of six.
    var controlButtonRows: [[ControlAction]] {
        stride(from: 0, to: controlButtons.count, by: Self.buttonsPerRow).map {
            Array(controlButtons[$0..<min($0 + Self.buttonsPerRow, controlButtons.count)])
        }
    }

    /// Whether a toggle button is on, so it can light up.
    func isOn(_ action: ControlAction) -> Bool {
        switch action {
        case .keepAwake: return toggles.keepAwake
        case .darkMode: return toggles.darkMode
        case .nightShift: return toggles.nightShift
        case .mute: return volumeMuted
        case .micMute: return toggles.microphoneMuted
        case .wifi: return toggles.wifiOn
        case .bluetooth: return toggles.bluetoothOn
        case .dockAutohide: return toggles.dockHidden
        case .hiddenFiles: return toggles.hiddenFilesShown
        case .speedTest: return isTestingSpeed
        case .focus: return focus.isOn
        case .desktopIcons: return toggles.desktopIconsHidden
        default: return false
        }
    }

    /// Rows are 10 pt apart, below the notch, with room at the bottom.
    private var controlsHeight: CGFloat {
        var rows: [CGFloat] = []
        if !controlTiles.isEmpty { rows.append(96) }
        if settings.showVolumeSlider { rows.append(40) }
        let buttonRows = CGFloat(controlButtonRows.count)
        if buttonRows > 0 { rows.append(buttonRows * Self.controlButtonSize + (buttonRows - 1) * 12 + 2) }
        if rows.isEmpty { rows.append(20) }
        return max(60, rows.reduce(0) { $0 + $1 + 10 } + 18)
    }

    func perform(_ action: ControlAction) {
        switch action {
        case .none: break
        case .keepAwake: toggles.toggleKeepAwake()
        case .darkMode:
            toggles.toggleDarkMode { [weak self] worked in
                guard !worked, let self else { return }
                self.collapse()
                self.show(.message(text: "Allow Halo to control System Events", symbol: "exclamationmark.triangle.fill"))
            }
        case .nightShift: toggles.toggleNightShift()
        case .micMute:
            if !toggles.toggleMicrophone() {
                announce("This microphone can't be muted", symbol: "mic.slash")
            }
        case .wifi:
            if !toggles.toggleWiFi() {
                announce("Couldn't change Wi-Fi", symbol: "wifi.exclamationmark")
            }
        case .bluetooth: toggles.toggleBluetooth()
        case .dockAutohide:
            toggles.toggleDockAutohide { [weak self] worked in
                guard !worked else { return }
                self?.announce("Allow Halo to control System Events", symbol: "exclamationmark.triangle.fill")
            }
        case .timer: showPage(.timer)
        case .notes: showPage(.notes)
        case .emptyTrash: emptyTrash()
        case .hiddenFiles: toggles.toggleHiddenFiles()
        case .clearClipboard:
            collapse()
            NSPasteboard.general.clearContents()
            show(.success(text: "Clipboard cleared"))
        case .airDrop:
            collapse()
            QuickAction.openApp(at: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        case .calculator:
            collapse()
            QuickAction.openApp(at: "/System/Applications/Calculator.app")
        case .activityMonitor:
            collapse()
            QuickAction.openApp(at: "/System/Applications/Utilities/Activity Monitor.app")
        case .copyIP:
            collapse()
            if let address = QuickAction.localIPAddress() {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                show(.success(text: "Copied \(address)"))
            } else {
                show(.message(text: "Not connected to a network", symbol: "network.slash"))
            }
        case .speedTest:
            guard !isTestingSpeed else { return }
            isTestingSpeed = true
            collapse()
            show(.message(text: "Testing internet speed…", symbol: "gauge.with.dots.needle.33percent"))
            Task { [weak self] in
                let result = await QuickAction.speedTest()
                guard let self else { return }
                self.isTestingSpeed = false
                if let result {
                    self.announce(String(format: "↓ %.0f Mbps   ↑ %.0f Mbps", result.down, result.up), symbol: "gauge.with.dots.needle.67percent")
                } else {
                    self.announce("Speed test didn't finish", symbol: "wifi.exclamationmark")
                }
            }
        case .restart:
            collapse()
            QuickAction.showPowerDialog(restart: true)
        case .shutDown:
            collapse()
            QuickAction.showPowerDialog(restart: false)
        case .mute: toggleMute()
        case .desktopIcons: toggles.toggleDesktopIcons()
        case .colorPicker:
            collapse()
            QuickAction.pickColor { [weak self] hex in
                guard let hex else { return }
                self?.show(.success(text: "Copied \(hex)"))
            }
        case .showDesktop:
            collapse()
            NSWorkspace.shared.hideOtherApplications()
        case .missionControl:
            collapse()
            QuickAction.openSystemApp("Mission Control")
        case .apps:
            collapse()
            QuickAction.openSystemApp("Apps")
        case .sleep:
            collapse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { QuickAction.sleepMac() }
        case .ejectDisks:
            collapse()
            Task { [weak self] in
                let count = await QuickAction.ejectAll()
                self?.show(count.ejected == 0 && count.failed == 0 ? .message(text: "No disks to eject", symbol: "eject")
                           : count.failed > 0 ? .message(text: "Couldn't eject \(count.failed) disk\(count.failed == 1 ? "" : "s")", symbol: "exclamationmark.triangle.fill")
                           : .success(text: "Ejected \(count.ejected) disk\(count.ejected == 1 ? "" : "s")"))
            }
        case .clipboard:
            collapse()
            openClipboard()
        case .clearCaches: clearCaches()
        case .forceQuit: forceQuitAllApps()
        case .lockScreen:
            collapse()
            QuickAction.lockScreen()
        case .screenshot:
            collapse()
            // After the island has closed, so it isn't in the picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { QuickAction.takeScreenshot() }
        case .focus: toggleFocus()
        case .sleepDisplay:
            collapse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { QuickAction.sleepDisplay() }
        case .weather: showPage(.weather)
        case .settings:
            collapse()
            openSettings()
        }
    }

    private func navigationRoom(for content: ExpandedContent) -> CGFloat {
        isPage(content) ? Self.navigationHeight : 0
    }

    /// The largest the island ever gets, so the window can be sized once.
    var maximumExtent: CGSize {
        let bubble = (notchSize.height + IslandLayout.bubbleGap) * 2
        return CGSize(width: max(460 + bubble, notchSize.width + 112 * 2, notchSize.width + (notchSize.height + 42) * 2 + bubble),
                      height: notchSize.height + 330)
    }

    // MARK: Alerts

    func show(_ event: TransientEvent) {
        guard settings.isEnabled, !isFullScreen else { return }
        if expanded != nil {
            // Only important alerts interrupt someone using the expanded island;
            // the volume and brightness keys still get their feedback in place.
            switch event {
            case .lowBattery: expanded = nil
            default:
                islandLog.debug("skip \(event.kind, privacy: .public): expanded")
                return
            }
        }
        if let transient, transient.isImportant, !event.isImportant { return }

        transient = event
        islandLog.notice("show \(event.kind, privacy: .public)")
        scheduleTransientDismissal(after: event.duration)
        if event.isImportant { haptic(.levelChange) }
    }

    private func scheduleTransientDismissal(after delay: TimeInterval) {
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Don't pull a card away while the pointer is on it.
            if self.isHovering, self.transient?.isCard == true {
                self.scheduleTransientDismissal(after: 1)
            } else {
                self.dismissTransient()
            }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismissTransient() {
        transientWork?.cancel()
        transientWork = nil
        guard let ended = transient else { return }
        transient = nil
        islandLog.debug("end \(ended.kind, privacy: .public)")
    }

    // MARK: Pointer

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering

        if hovering {
            collapseWork?.cancel()
            collapseWork = nil
            if settings.expandOnHover, expanded == nil, transient == nil, case let .compact(activity, _) = presentation,
               activity != .privacy {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isHovering, self.expanded == nil else { return }
                    self.expand(self.content(for: activity))
                }
                hoverExpandWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        } else {
            hoverExpandWork?.cancel()
            hoverExpandWork = nil
            scheduleCollapseIfNeeded()
        }
    }

    /// Collapses once the pointer has left. `delay` is longer when the island opened
    /// on its own (a button elsewhere, a drop) and the pointer was never on it.
    func scheduleCollapseIfNeeded(delay: TimeInterval = 1) {
        guard expanded != nil, !isHovering, !isDraggingOut, !isDropTargeted, !isMenuOpen else { return }
        collapseWork?.cancel()
        // A freshly opened island stays put for a few seconds, so there's time to reach it.
        let wait = max(delay, holdUntil.timeIntervalSinceNow)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isHovering, !self.isDraggingOut, !self.isDropTargeted, !self.isMenuOpen else {
                self.collapseWork = nil
                return
            }
            if self.holdUntil.timeIntervalSinceNow > 0.05 {
                self.scheduleCollapseIfNeeded(delay: 0)
                return
            }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// How long an island just opened by a click stays open without the pointer on it.
    static let openHold: TimeInterval = 3.5
    private var holdUntil = Date.distantPast

    func setFullScreen(_ fullScreen: Bool) {
        guard isFullScreen != fullScreen else { return }
        isFullScreen = fullScreen
        if fullScreen { reset() }
    }

    func setMenuOpen(_ open: Bool) {
        guard isMenuOpen != open else { return }
        isMenuOpen = open
        if !open { scheduleCollapseIfNeeded(delay: 1.5) }
    }

    /// Hides the current track until a new one starts (the menu's "Hide Until Next Song").
    func dismissNowPlaying() {
        collapse()
        dismissed.insert(.nowPlaying)
    }

    /// Empties the Trash through Finder, after asking, since it can't be undone.
    func emptyTrash() {
        collapse()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Everything in the Trash is deleted for good. You can't undo this."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
            DispatchQueue.main.async { [weak self] in
                if error == nil {
                    self?.show(.success(text: "Trash emptied"))
                } else {
                    self?.show(.message(text: "Allow Halo to control Finder", symbol: "exclamationmark.triangle.fill"))
                }
            }
        }
    }

    /// Clears app caches to free storage, after showing how much and asking.
    func clearCaches() {
        collapse()
        show(.message(text: "Checking caches…", symbol: "trash.fill"))
        let running = NSWorkspace.shared.runningApplications
        let ids = Set(running.compactMap(\.bundleIdentifier))
        var names: [String: String] = [:]
        for app in running {
            if let id = app.bundleIdentifier, let name = app.localizedName { names[id] = name }
        }
        Task.detached(priority: .userInitiated) {
            let plan = CacheCleaner.plan(runningBundleIDs: ids, runningNames: names)
            await MainActor.run { [weak self] in self?.confirmClearing(plan) }
        }
    }

    private func confirmClearing(_ plan: CacheCleaner.Plan) {
        dismissTransient()
        guard plan.bytes >= 1_000_000 else {
            show(.success(text: "Caches are already tidy"))
            return
        }
        let size = CacheCleaner.format(plan.bytes)
        let alert = NSAlert()
        alert.messageText = "Clear \(size) of app caches?"
        var details = "These are files apps keep to load faster; they rebuild them as needed. Nothing personal is deleted, and system files are left alone."
        let regularApps = plan.skippedApps.filter { name in
            NSWorkspace.shared.runningApplications.contains { $0.localizedName == name && $0.activationPolicy == .regular }
        }
        if !regularApps.isEmpty {
            details += "\n\nSkipped because they're open: \(regularApps.prefix(6).joined(separator: ", "))\(regularApps.count > 6 ? " and more" : "")."
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        show(.message(text: "Clearing caches…", symbol: "trash.fill"))
        Task.detached(priority: .userInitiated) {
            let freed = CacheCleaner.clear(plan)
            await MainActor.run { [weak self] in
                self?.dismissTransient()
                self?.show(.success(text: "Cleaned up \(CacheCleaner.format(freed))"))
            }
        }
    }

    /// Force quits every open app, after asking. Unsaved work is lost, so this is
    /// never a single unconfirmed click.
    func forceQuitAllApps() {
        let apps = QuickAction.quittableApps()
        guard !apps.isEmpty else {
            show(.message(text: "No apps to quit", symbol: "checkmark"))
            return
        }
        let names = apps.compactMap(\.localizedName).sorted()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Force quit \(apps.count) app\(apps.count == 1 ? "" : "s")?"
        alert.informativeText = """
        \(names.prefix(8).joined(separator: ", "))\(names.count > 8 ? " and \(names.count - 8) more" : "").

        Force quitting doesn't save anything first, so unsaved work in these apps is lost.
        """
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        // Cancel is the safe default: Return and Escape both cancel.
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        collapse()
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let quit = QuickAction.forceQuitAll()
        show(.success(text: "Force quit \(quit) app\(quit == 1 ? "" : "s")"))
    }

    /// Toggles Focus from the Controls page.
    func toggleFocus() {
        focus.toggle { [weak self] text, worked in
            guard let self else { return }
            if worked {
                self.show(.success(text: text))
            } else {
                self.show(.message(text: text, symbol: "exclamationmark.triangle"))
            }
        }
    }

    /// Puts the current artwork in the clipboard history.
    func saveArtworkToClipboard() -> Bool {
        guard let artwork = nowPlaying.artwork else { return false }
        return clipboard.add(image: artwork, source: nowPlaying.track.map { appName(for: $0.bundleID) }) != nil
    }

    func setPressed(_ pressed: Bool) {
        if isPressed != pressed { isPressed = pressed }
    }

    func setDropTargeted(_ targeted: Bool) {
        guard targeted != isDropTargeted else { return }
        isDropTargeted = targeted
        guard settings.clipboardHistory else { return }
        if targeted {
            // A bigger card to drop onto than the notch itself.
            collapse()
            show(.dropTarget)
        } else if transient == .dropTarget {
            dismissTransient()
        }
    }

    // MARK: Gestures

    /// A click: opens the activity's app, like a tap on iPhone — or expands, if
    /// "Click to expand" is on or the activity has no app.
    func tap() {
        switch presentation {
        case .idle:
            expandIdle()
        case let .compact(activity, _):
            // The camera and microphone dots are an indicator, not something to open.
            guard activity != .privacy else { return }
            if activity == .download {
                _ = openApp(for: activity)
                return
            }
            if settings.clickExpands || !openApp(for: activity) {
                expand(content(for: activity))
            }
        case let .transient(event):
            if case let .download(download) = event {
                dismissTransient()
                NSWorkspace.shared.activateFileViewerSelecting([download.url])
                return
            }
            if case .screenshot = event {
                dismissTransient()
                openClipboard()
                return
            }
            if case .copied = event {
                dismissTransient()
                openClipboard()
                return
            }
            dismissTransient()
            if case let .compact(activity, _) = presentation {
                expand(content(for: activity))
            }
        case .expanded:
            break
        }
    }

    /// Press and hold: expands without opening the app (or opens it, when clicks expand).
    func longPress() {
        haptic(.alignment)
        switch presentation {
        case .idle:
            expandIdle()
        case let .compact(activity, _):
            guard activity != .privacy else { return }
            if settings.clickExpands, openApp(for: activity) { return }
            expand(content(for: activity))
        case let .transient(event):
            guard !event.isCard else { return }
            dismissTransient()
            expandIdle()
        case .expanded:
            break
        }
    }

    // MARK: Pages

    /// The expanded views you can move between with the icons at the bottom of the
    /// island (or a two-finger swipe), in the order they appear there.
    var pages: [ExpandedContent] {
        var result: [ExpandedContent] = []
        let hasTrack = settings.showNowPlaying && nowPlaying.track != nil
        if hasTrack { result.append(.nowPlaying) }
        if hasTrack, settings.isPageOn(.lyrics) { result.append(.lyrics) }
        result.append(.controls)
        if settings.usesWeather { result.append(.weather) }
        if settings.showCalendar, calendar.next != nil { result.append(.calendar) }
        if settings.isPageOn(.timer) || timer.isActive { result.append(.timer) }
        if settings.isPageOn(.system) { result.append(.system) }
        if settings.isPageOn(.reminders) { result.append(.reminders) }
        if settings.isPageOn(.notes) { result.append(.notes) }
        if settings.isPageOn(.shortcuts) { result.append(.shortcuts) }
        if settings.isPageOn(.mirror) { result.append(.mirror) }
        return result
    }

    func isPage(_ content: ExpandedContent) -> Bool {
        pages.contains(content)
    }

    func showPage(_ content: ExpandedContent) {
        guard expanded != content else { return }
        holdUntil = max(holdUntil, Date().addingTimeInterval(2.5))
        if let current = expanded, let from = pages.firstIndex(of: current), let to = pages.firstIndex(of: content) {
            pageStep = to > from ? 1 : -1
        } else {
            pageStep = 0
        }
        expanded = content
        haptic(.alignment)
        islandLog.notice("page \(String(describing: content), privacy: .public)")
    }

    /// A two-finger swipe: pages when the island is open; on a compact song, the next
    /// or previous track.
    func swipe(_ step: Int) {
        if expanded != nil {
            stepPage(by: step)
        } else if case .compact(.nowPlaying, _) = presentation {
            step > 0 ? nowPlaying.next() : nowPlaying.previous()
            haptic(.alignment)
        }
    }

    /// The keyboard shortcut: open what a click would open, or close the island.
    func toggleFromShortcut() {
        if expanded != nil {
            collapse()
        } else if case let .compact(activity, _) = presentation, activity != .privacy {
            expand(content(for: activity))
        } else {
            expandIdle()
        }
    }

    /// Moves one page left or right, as a two-finger swipe does.
    func stepPage(by step: Int) {
        guard let current = expanded, let index = pages.firstIndex(of: current) else { return }
        let next = index + step
        guard pages.indices.contains(next) else { return }
        showPage(pages[next])
    }

    /// The island has nothing live: open the last track's controls, or the controls if
    /// it has something on it. With neither, a click only gives the press feedback.
    private func expandIdle() {
        switch IdlePage(rawValue: settings.idlePage) ?? .automatic {
        case .weather:
            expand(.weather)
        case .controls:
            expand(.controls)
        case .automatic:
            if settings.showNowPlaying, nowPlaying.track != nil {
                expand(.nowPlaying)
            } else {
                expand(.controls)
            }
        }
    }

    /// Swipe up: dismisses what's showing, like flicking a Live Activity away.
    func swipeUp() {
        switch presentation {
        case .idle:
            break
        case let .compact(activity, _):
            dismissed.insert(activity)
            haptic(.generic)
            islandLog.notice("dismiss \(String(describing: activity), privacy: .public)")
        case .transient:
            dismissTransient()
        case .expanded:
            collapse()
        }
    }

    func tapMinimal() {
        guard let minimal = presentation.minimal else { return }
        expand(content(for: minimal))
    }

    func expand(_ content: ExpandedContent) {
        if let transient, !transient.isImportant { dismissTransient() }
        guard expanded != content else { return }
        pageStep = 0
        holdUntil = Date().addingTimeInterval(Self.openHold)
        if let activity = activity(for: content) { undismiss(activity) }
        expanded = content
        islandLog.notice("expand \(String(describing: content), privacy: .public)")
        haptic(.levelChange)
        scheduleCollapseIfNeeded(delay: 4)
    }

    func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard expanded != nil else { return }
        expanded = nil
        islandLog.notice("collapse")
    }

    func reset() {
        transientWork?.cancel()
        collapseWork?.cancel()
        hoverExpandWork?.cancel()
        transient = nil
        expanded = nil
        isHovering = false
        isDropTargeted = false
        isPressed = false
        isDraggingOut = false
    }

    // MARK: Actions

    @discardableResult
    private func openApp(for activity: Activity) -> Bool {
        switch activity {
        case .nowPlaying:
            guard nowPlaying.track?.bundleID != nil else { return false }
            nowPlaying.openSourceApp()
            collapse()
            return true
        case .call:
            guard let call = privacy.call else { return false }
            call.open()
            return true
        case .recording:
            guard let recording = privacy.recording else { return false }
            recording.open()
            return true
        case .calendar:
            calendar.openInCalendar()
            return true
        case .download:
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            return true
        case .screenRecording, .privacy, .timer:
            return false
        }
    }

    private func content(for activity: Activity) -> ExpandedContent {
        switch activity {
        case .call: return .call
        case .screenRecording: return .screenRecording
        case .recording: return .recording
        case .nowPlaying: return .nowPlaying
        case .calendar: return .calendar
        case .timer: return .timer
        case .privacy, .download: return .controls
        }
    }

    private func activity(for content: ExpandedContent) -> Activity? {
        switch content {
        case .call: return .call
        case .screenRecording: return .screenRecording
        case .recording: return .recording
        case .nowPlaying: return .nowPlaying
        case .calendar: return .calendar
        case .timer: return .timer
        case .controls, .weather, .lyrics, .system, .reminders, .notes, .shortcuts, .mirror, .smartDrop: return nil
        }
    }

    func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard settings.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
