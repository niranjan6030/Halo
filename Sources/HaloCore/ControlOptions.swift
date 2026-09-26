import Foundation

/// A tile at the top of the Controls page.
public enum ControlTileKind: String, CaseIterable, Identifiable, Sendable {
    case none, battery, focus, weather, nowPlaying, clipboard, system, timer, note, date, network, storage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .battery: return "Battery"
        case .focus: return "Focus"
        case .weather: return "Weather"
        case .nowPlaying: return "Now Playing"
        case .clipboard: return "Clipboard"
        case .system: return "CPU and Memory"
        case .timer: return "Timer"
        case .note: return "Quick Note"
        case .date: return "Date and Next Event"
        case .network: return "Network Speed"
        case .storage: return "Storage"
        }
    }

    public var symbol: String {
        switch self {
        case .system: return "cpu"
        case .timer: return "timer"
        case .note: return "note.text"
        case .date: return "calendar"
        case .network: return "arrow.up.arrow.down"
        case .storage: return "internaldrive"
        case .none: return "circle.dashed"
        case .battery: return "battery.100percent"
        case .focus: return "moon.fill"
        case .weather: return "cloud.sun.fill"
        case .nowPlaying: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

/// A round button along the bottom of the Controls page.
public enum ControlAction: String, CaseIterable, Identifiable, Sendable {
    case none
    // Toggles, which light up while on.
    case keepAwake, darkMode, nightShift, mute, micMute, wifi, bluetooth, focus, dockAutohide, desktopIcons, hiddenFiles
    // One-shot actions.
    case clipboard, clearClipboard, screenshot, colorPicker, airDrop, showDesktop, missionControl, apps
    case calculator, activityMonitor, speedTest, copyIP
    case timer, notes, lockScreen, sleepDisplay, sleep, restart, shutDown, ejectDisks, emptyTrash
    case clearCaches, forceQuit, weather, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .keepAwake: return "Keep Awake"
        case .darkMode: return "Dark Mode"
        case .nightShift: return "Night Shift"
        case .mute: return "Mute"
        case .micMute: return "Mute Microphone"
        case .wifi: return "Wi-Fi"
        case .bluetooth: return "Bluetooth"
        case .dockAutohide: return "Hide Dock"
        case .timer: return "Timer"
        case .notes: return "Quick Note"
        case .emptyTrash: return "Empty Trash"
        case .hiddenFiles: return "Show Hidden Files"
        case .clearClipboard: return "Clear Clipboard"
        case .airDrop: return "AirDrop"
        case .calculator: return "Calculator"
        case .activityMonitor: return "Activity Monitor"
        case .speedTest: return "Internet Speed Test"
        case .copyIP: return "Copy IP Address"
        case .restart: return "Restart…"
        case .shutDown: return "Shut Down…"
        case .focus: return "Focus"
        case .desktopIcons: return "Hide Desktop Icons"
        case .clipboard: return "Clipboard"
        case .screenshot: return "Screenshot"
        case .colorPicker: return "Color Picker"
        case .showDesktop: return "Show Desktop"
        case .missionControl: return "Mission Control"
        case .apps: return "Apps"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        case .sleep: return "Sleep"
        case .ejectDisks: return "Eject All Disks"
        case .clearCaches: return "Clear App Caches"
        case .forceQuit: return "Force Quit Apps"
        case .weather: return "Weather"
        case .settings: return "Halo Settings"
        }
    }

    public var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .keepAwake: return "cup.and.saucer.fill"
        case .darkMode: return "circle.lefthalf.filled"
        case .nightShift: return "sun.horizon.fill"
        case .mute: return "speaker.slash.fill"
        case .micMute: return "mic.slash.fill"
        case .wifi: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .dockAutohide: return "dock.rectangle"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .emptyTrash: return "trash"
        case .hiddenFiles: return "eye.circle"
        case .clearClipboard: return "clipboard"
        case .airDrop: return "dot.radiowaves.up.forward"
        case .calculator: return "plus.forwardslash.minus"
        case .activityMonitor: return "waveform.path.ecg"
        case .speedTest: return "gauge.with.dots.needle.67percent"
        case .copyIP: return "network"
        case .restart: return "restart"
        case .shutDown: return "power"
        case .focus: return "moon.fill"
        case .desktopIcons: return "eye.slash"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .colorPicker: return "eyedropper"
        case .showDesktop: return "menubar.dock.rectangle"
        case .missionControl: return "rectangle.3.group"
        case .apps: return "square.grid.3x3.fill"
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "display"
        case .sleep: return "powersleep"
        case .ejectDisks: return "eject.fill"
        case .clearCaches: return "trash.fill"
        case .forceQuit: return "xmark"
        case .weather: return "cloud.sun.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Optional pages in the island, each with its own icon in the row along the bottom.
public enum IslandPage: String, CaseIterable, Identifiable, Sendable {
    case lyrics, timer, system, devices, reminders, notes, shortcuts, mirror

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .shortcuts: return "Shortcuts"
        case .timer: return "Timer, Stopwatch and Pomodoro"
        case .system: return "CPU, FPS, Memory, Disk and Network"
        case .devices: return "Devices and batteries"
        case .reminders: return "Reminders"
        case .notes: return "Quick Note"
        case .mirror: return "Mirror"
        }
    }

    public var symbol: String {
        switch self {
        case .lyrics: return "quote.bubble.fill"
        case .shortcuts: return "square.stack.3d.up.fill"
        case .timer: return "timer"
        case .system: return "cpu"
        case .devices: return "battery.100percent"
        case .reminders: return "checklist"
        case .notes: return "note.text"
        case .mirror: return "camera.fill"
        }
    }

    public static let defaultPages = "lyrics,timer,system,devices,notes,shortcuts"
}

/// What a click on the island opens when nothing is running.
public enum IdlePage: String, CaseIterable, Identifiable, Sendable {
    case automatic, controls, weather

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Now Playing, or Controls"
        case .controls: return "Controls"
        case .weather: return "Weather"
        }
    }
}

public extension Settings {
    static let maximumButtons = 12
    static let defaultButtons = "clipboard,screenshot,keepAwake,darkMode,clearCaches,forceQuit"

    var leftTile: ControlTileKind { ControlTileKind(rawValue: controlsLeftTile) ?? .battery }
    var rightTile: ControlTileKind { ControlTileKind(rawValue: controlsRightTile) ?? .focus }

    /// The chosen buttons, in order.
    var buttons: [ControlAction] {
        controlsButtons.split(separator: ",")
            .compactMap { ControlAction(rawValue: String($0)) }
            .filter { $0 != .none }
            .prefix(Self.maximumButtons)
            .map { $0 }
    }

    /// Sets the button at `index`; `.none` removes it, and an index past the end adds one.
    func setButton(_ action: ControlAction, at index: Int) {
        var list = buttons
        if index < list.count {
            if action == .none { list.remove(at: index) } else { list[index] = action }
        } else if action != .none, list.count < Self.maximumButtons {
            list.append(action)
        }
        controlsButtons = list.map(\.rawValue).joined(separator: ",")
    }

    func isPageOn(_ page: IslandPage) -> Bool {
        extraPages.split(separator: ",").contains { $0 == page.rawValue }
    }

    func setPage(_ page: IslandPage, on: Bool) {
        let enabled = IslandPage.allCases.filter { $0 == page ? on : isPageOn($0) }
        extraPages = enabled.map(\.rawValue).joined(separator: ",")
    }

    /// Whether anything on the Controls page needs the weather.
    var usesWeather: Bool {
        showWeather || idlePage == IdlePage.weather.rawValue || leftTile == .weather || rightTile == .weather || buttons.contains(.weather)
    }
}
