import AppKit
import CoreAudio
import CoreMediaIO

/// An app doing something the island shows as a live activity.
struct AppActivity: Equatable {
    enum Kind {
        case call
        case recording
    }

    var kind: Kind
    var bundleID: String
    var name: String
    var started: Date

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Camera and microphone use, which app is on a call or recording, and whether
/// the screen is being recorded.
@MainActor
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraInUse = false
    @Published private(set) var microphoneInUse = false
    @Published private(set) var call: AppActivity?
    @Published private(set) var recording: AppActivity?
    @Published private(set) var screenRecordingSince: Date?
    @Published private(set) var microphoneMuted = false

    var isActive: Bool { cameraInUse || microphoneInUse }

    private var timer: Timer?

    /// Apps whose microphone use means a call.
    private static let callApps: Set<String> = [
        "com.apple.FaceTime", "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
        "com.skype.skype", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "ru.keepcoder.Telegram",
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.operasoftware.Opera",
    ]
    /// Apps whose microphone use means recording.
    private static let recordingApps: Set<String> = [
        "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX", "com.apple.garageband10", "com.apple.logic10",
        "org.audacityteam.audacity", "com.obsproject.obs-studio",
    ]
    /// System services that listen without it being anything to show (Siri, dictation).
    private static let ignored: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.assistantd", "com.apple.SiriNCService", "com.apple.corespeechd",
        "com.apple.universalaccessd", "com.apple.controlcenter", "com.apple.audiomxd",
    ]

    func start() {
        guard timer == nil else { return }
        poll()
        // Polled once a second: devices and processes come and go constantly, and a
        // poll never goes stale the way per-object listeners can.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cameraInUse = false
        microphoneInUse = false
        call = nil
        recording = nil
        screenRecordingSince = nil
    }

    // MARK: Microphone mute

    func toggleMicrophoneMute() {
        guard let device = Self.defaultInputDevice() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var value = UInt32(microphoneMuted ? 0 : 1)
        if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
            microphoneMuted.toggle()
        }
    }

    // MARK: Polling

    private func poll() {
        let camera = Self.anyCameraRunning()
        let microphone = Self.defaultInputRunning()
        if camera != cameraInUse { cameraInUse = camera }
        if microphone != microphoneInUse { microphoneInUse = microphone }

        let muted = Self.defaultInputMuted()
        if muted != microphoneMuted { microphoneMuted = muted }

        var callApp: (String, String)?
        var recordingApp: (String, String)?
        for (bundleID, name) in Self.appsUsingMicrophone() {
            if Self.callApps.contains(bundleID) { callApp = callApp ?? (bundleID, name) }
            else if Self.recordingApps.contains(bundleID) { recordingApp = recordingApp ?? (bundleID, name) }
        }
        // FaceTime and Continuity (iPhone) calls run in system daemons rather than FaceTime.app.
        if callApp == nil, Self.systemCallActive() {
            callApp = ("com.apple.FaceTime", "FaceTime")
        }

        update(&call, with: callApp, kind: .call)
        update(&recording, with: recordingApp, kind: .recording)

        let recordingScreen = Self.screenRecordingActive()
        if recordingScreen, screenRecordingSince == nil { screenRecordingSince = Date() }
        if !recordingScreen, screenRecordingSince != nil { screenRecordingSince = nil }
    }

    private func update(_ activity: inout AppActivity?, with app: (String, String)?, kind: AppActivity.Kind) {
        guard let (bundleID, name) = app else {
            if activity != nil { activity = nil }
            return
        }
        if activity?.bundleID != bundleID {
            activity = AppActivity(kind: kind, bundleID: bundleID, name: name, started: Date())
        }
    }

    // MARK: Core Audio

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func defaultInputRunning() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func defaultInputMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }
        return processes
    }

    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Apps (not helper processes) currently recording from any microphone.
    private static func appsUsingMicrophone() -> [(String, String)] {
        var result: [(String, String)] = []
        for process in audioProcesses() where isRunningInput(process) {
            guard let pid = pid(of: process), let app = owningApp(pid: pid),
                  let bundleID = app.bundleIdentifier, !ignored.contains(bundleID) else { continue }
            if !result.contains(where: { $0.0 == bundleID }) {
                result.append((bundleID, app.localizedName ?? bundleID))
            }
        }
        return result
    }

    /// Browser tabs and Electron apps record from helper processes inside the app
    /// bundle; walk up to the .app the user actually knows.
    private static func owningApp(pid: pid_t) -> NSRunningApplication? {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return nil }
        if running.activationPolicy == .regular { return running }
        guard let path = running.bundleURL?.path ?? running.executableURL?.path,
              let range = path.range(of: ".app/") else { return running.bundleIdentifier == nil ? nil : running }
        let outerAppPath = String(path[..<range.lowerBound]) + ".app"
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == outerAppPath } ?? running
    }

    private static func systemCallActive() -> Bool {
        audioProcesses().contains { process in
            guard isRunningInput(process), let bundleID = bundleID(of: process) else { return false }
            return bundleID == "com.apple.avconferenced" || bundleID == "com.apple.TelephonyUtilities"
        }
    }

    // MARK: Camera and screen

    private static func anyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == 0, dataSize > 0 else { return false }

        var devices = [CMIOObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &used, &devices) == 0 else { return false }

        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for device in devices {
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                         &runningUsed, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    /// macOS's own screen recording (Shift-Command-5) puts a stop button in the menu
    /// bar, owned by screencaptureui; it exists only while a recording runs.
    private static func screenRecordingActive() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windows.contains { window in
            window[kCGWindowOwnerName as String] as? String == "screencaptureui"
                && window[kCGWindowLayer as String] as? Int == statusLevel
        }
    }
}
