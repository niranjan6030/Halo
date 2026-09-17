import AppKit
import CoreAudio
import CoreWLAN
import IOBluetooth
import ObjectiveC

@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
private func bluetoothPowerState() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
private func setBluetoothPowerState(_ state: Int32)

/// The on/off switches the Controls page can offer: Keep Awake, Dark Mode, Night Shift
/// and desktop icons. Each reads the system's real state, so the buttons stay right
/// when the same thing is changed somewhere else.
@MainActor
final class SystemToggles: ObservableObject {
    @Published private(set) var keepAwake = false
    @Published private(set) var darkMode = false
    @Published private(set) var nightShift = false
    @Published private(set) var desktopIconsHidden = false
    @Published private(set) var wifiOn = false
    @Published private(set) var bluetoothOn = false
    @Published private(set) var microphoneMuted = false
    @Published private(set) var dockHidden = false
    @Published private(set) var hiddenFilesShown = false

    private var caffeinate: Process?
    private lazy var blueLight = BlueLightClient()

    init() {
        refresh()
    }

    /// Bluetooth's state is read only when a Bluetooth button is showing: asking the
    /// controller counts as using Bluetooth, which macOS checks permission for.
    func refresh(includeBluetooth: Bool = false) {
        let dark = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
        if darkMode != dark { darkMode = dark }
        let hidden = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString) as? Bool == false
        if desktopIconsHidden != hidden { desktopIconsHidden = hidden }
        let shift = blueLight?.isEnabled ?? false
        if nightShift != shift { nightShift = shift }
        let awake = caffeinate?.isRunning == true
        if keepAwake != awake { keepAwake = awake }
        let wifi = CWWiFiClient.shared().interface()?.powerOn() ?? false
        if wifiOn != wifi { wifiOn = wifi }
        if includeBluetooth {
            let bluetooth = bluetoothPowerState() != 0
            if bluetoothOn != bluetooth { bluetoothOn = bluetooth }
        }
        let mic = Microphone.isMuted
        if microphoneMuted != mic { microphoneMuted = mic }
        let dock = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
        if dockHidden != dock { dockHidden = dock }
        let finderValue = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString)
        let shown = (finderValue as? Bool) ?? ((finderValue as? String).map { ["yes", "true", "1"].contains($0.lowercased()) } ?? false)
        if hiddenFilesShown != shown { hiddenFilesShown = shown }
    }

    // MARK: Keep Awake

    /// Stops the Mac and its display sleeping, like `caffeinate`, until turned off or
    /// Island quits (`-w` ties it to this process).
    func toggleKeepAwake() {
        if let caffeinate, caffeinate.isRunning {
            caffeinate.terminate()
            self.caffeinate = nil
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            do {
                try process.run()
                caffeinate = process
            } catch {
                islandLog.error("caffeinate failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        refresh()
    }

    // MARK: Dark Mode

    /// Switches appearance through System Events, which macOS asks about once.
    func toggleDarkMode(completion: @escaping (Bool) -> Void) {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            DispatchQueue.main.async { [weak self] in
                // The global default is written a moment after the switch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
                completion(error == nil)
            }
        }
    }

    // MARK: Wi-Fi, Bluetooth, microphone, Dock

    func toggleWiFi() -> Bool {
        guard let interface = CWWiFiClient.shared().interface() else { return false }
        do {
            try interface.setPower(!interface.powerOn())
        } catch {
            islandLog.error("wifi power failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        refresh()
        return true
    }

    func toggleBluetooth() {
        setBluetoothPowerState(bluetoothPowerState() != 0 ? 0 : 1)
        // The controller takes a moment to come up or go down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh(includeBluetooth: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh(includeBluetooth: true) }
    }

    func toggleMicrophone() -> Bool {
        let worked = Microphone.setMuted(!Microphone.isMuted)
        refresh()
        return worked
    }

    /// Dock auto-hide through System Events (the permission Dark Mode also uses).
    func toggleDockAutohide(completion: @escaping (Bool) -> Void) {
        let script = "tell application \"System Events\" to tell dock preferences to set autohide to not autohide"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refresh()
                completion(error == nil)
            }
        }
    }

    // MARK: Night Shift

    var canUseNightShift: Bool { blueLight != nil }

    func toggleNightShift() {
        guard let blueLight else { return }
        blueLight.setEnabled(!blueLight.isEnabled)
        refresh()
    }

    // MARK: Hidden files

    /// Shows or hides dotfiles and other hidden files in Finder (Finder restarts to apply it).
    func toggleHiddenFiles() {
        let show = !hiddenFilesShown
        CFPreferencesSetAppValue("AppleShowAllFiles" as CFString, show as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        hiddenFilesShown = show
    }

    // MARK: Desktop icons

    /// Hides or shows the files on the desktop (Finder restarts to apply it).
    func toggleDesktopIcons() {
        let hide = !desktopIconsHidden
        CFPreferencesSetAppValue("CreateDesktop" as CFString, (!hide) as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        desktopIconsHidden = hide
    }
}

/// Night Shift through CoreBrightness's CBBlueLightClient, the object Control Center uses.
private final class BlueLightClient {
    private let client: NSObject

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        let client = type.init()
        guard client.responds(to: NSSelectorFromString("getBlueLightStatus:")),
              client.responds(to: NSSelectorFromString("setEnabled:")) else { return nil }
        self.client = client
    }

    /// The status struct starts { BOOL active; BOOL enabled; … }; 64 bytes covers all of it.
    var isEnabled: Bool {
        let status = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { status.deallocate() }
        status.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        typealias GetStatus = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        let selector = NSSelectorFromString("getBlueLightStatus:")
        let function = unsafeBitCast(client.method(for: selector), to: GetStatus.self)
        guard function(client, selector, status) else { return false }
        return status.load(fromByteOffset: 1, as: UInt8.self) != 0
    }

    func setEnabled(_ enabled: Bool) {
        typealias SetEnabled = @convention(c) (NSObject, Selector, Bool) -> Bool
        let selector = NSSelectorFromString("setEnabled:")
        let function = unsafeBitCast(client.method(for: selector), to: SetEnabled.self)
        _ = function(client, selector, enabled)
    }
}

/// The default input device's mute. Devices without a mute switch are muted by
/// turning their input level to zero, and the old level comes back on unmute.
private enum Microphone {
    private static let restoreKey = "microphone.restoreLevel"

    private static var device: AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func canSet(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = inputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static var isMuted: Bool {
        guard let device else { return false }
        var address = inputAddress(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(device, &address) {
            var mute: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr, mute != 0 { return true }
        }
        var volume = inputAddress(kAudioDevicePropertyVolumeScalar)
        var level: Float32 = 1
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &volume),
           AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &level) == noErr {
            return level <= 0.001
        }
        return false
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let device else { return false }
        if canSet(device, kAudioDevicePropertyMute) {
            var address = inputAddress(kAudioDevicePropertyMute)
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            if status == noErr {
                // A level left at zero by the fallback would keep it silent.
                if !muted { restoreLevel(device) }
                return true
            }
        }
        guard canSet(device, kAudioDevicePropertyVolumeScalar) else { return false }
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        var level: Float32 = 0
        if muted {
            var current: Float32 = 1
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr, current > 0.001 {
                UserDefaults.standard.set(current, forKey: restoreKey)
            }
            level = 0
        } else {
            level = UserDefaults.standard.object(forKey: restoreKey) as? Float32 ?? 0.75
        }
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    }

    private static func restoreLevel(_ device: AudioObjectID) {
        guard canSet(device, kAudioDevicePropertyVolumeScalar) else { return }
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        var current: Float32 = 1
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr, current <= 0.001 else { return }
        var level = UserDefaults.standard.object(forKey: restoreKey) as? Float32 ?? 0.75
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
    }
}
