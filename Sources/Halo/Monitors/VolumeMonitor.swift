import AudioToolbox
import CoreAudio
import Foundation

struct AudioOutputInfo: Equatable {
    var name: String
    var symbol: String
    /// Only some outputs are worth announcing (AirPlay, displays, back to the speakers).
    var isNotable: Bool
}

/// Watches — and, for the media keys, sets — the default output device's volume
/// and mute state. Also reports when the output device itself changes.
@MainActor
final class VolumeMonitor {
    var onChange: ((_ volume: Float, _ muted: Bool) -> Void)?
    var onOutputChange: ((AudioOutputInfo) -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var lastVolume: Float?
    private var lastMuted: Bool?
    private var isRunning = false

    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.attachToDefaultDevice(announce: true) }
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.deviceChanged() }
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isRunning else { return }
        isRunning = true
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress,
                                            DispatchQueue.main, defaultDeviceListener)
        attachToDefaultDevice(announce: false)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress,
                                               DispatchQueue.main, defaultDeviceListener)
        detach()
    }

    // MARK: Control (media keys)

    /// The output level right now, for the island's volume slider.
    func currentLevel() -> (volume: Float, muted: Bool)? {
        refreshDevice()
        guard let volume = readVolume() else { return nil }
        return (volume, readMuted() ?? false)
    }

    /// Sets the level directly (the island's slider), clamped to 0...1.
    func setVolume(_ level: Float) {
        guard canSetVolume else { return }
        var value = Float32(min(1, max(0, level)))
        AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if value > 0, readMuted() == true { setMuted(false) }
        lastVolume = value
        lastMuted = readMuted() ?? false
    }

    var canSetVolume: Bool {
        refreshDevice()
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &Self.volumeAddress)
            && AudioObjectIsPropertySettable(device, &Self.volumeAddress, &settable) == noErr && settable.boolValue
    }

    /// Changes the volume by `step` (positive or negative) and returns the new state.
    func adjustVolume(by step: Float) -> (volume: Float, muted: Bool)? {
        guard canSetVolume, var volume = readVolume() else { return nil }
        // Snap to the grid so repeated presses land on the same levels macOS uses.
        let steps = (1 / abs(step)).rounded()
        volume = ((volume * steps).rounded() + (step > 0 ? 1 : -1)) / steps
        volume = min(1, max(0, volume))
        var value = Float32(volume)
        AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)

        var muted = readMuted() ?? false
        if muted && step > 0 {
            setMuted(false)
            muted = false
        } else if volume == 0 && !muted {
            setMuted(true)
            muted = true
        }
        lastVolume = volume
        lastMuted = muted
        return (volume, muted)
    }

    func toggleMute() -> (volume: Float, muted: Bool)? {
        guard canSetVolume, let volume = readVolume() else { return nil }
        let muted = !(readMuted() ?? false)
        setMuted(muted)
        lastVolume = volume
        lastMuted = muted
        return (volume, muted)
    }

    private func setMuted(_ muted: Bool) {
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &Self.muteAddress),
              AudioObjectIsPropertySettable(device, &Self.muteAddress, &settable) == noErr, settable.boolValue else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Device tracking

    private func refreshDevice() {
        if device == kAudioObjectUnknown || !isRunning {
            var current = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress,
                                          0, nil, &size, &current) == noErr {
                device = current
            }
        }
    }

    private func attachToDefaultDevice(announce: Bool) {
        guard isRunning else { return }
        var newDevice = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress,
                                                0, nil, &size, &newDevice)
        guard status == noErr, newDevice != device else { return }

        detach()
        device = newDevice
        if AudioObjectHasProperty(device, &Self.volumeAddress) {
            AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, DispatchQueue.main, deviceListener)
        }
        if AudioObjectHasProperty(device, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, DispatchQueue.main, deviceListener)
        }
        lastVolume = readVolume()
        lastMuted = readMuted()

        if announce {
            onOutputChange?(Self.outputInfo(for: device))
        }
    }

    private func detach() {
        guard device != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, DispatchQueue.main, deviceListener)
        AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, DispatchQueue.main, deviceListener)
        device = AudioDeviceID(kAudioObjectUnknown)
    }

    private func deviceChanged() {
        guard isRunning, let volume = readVolume() else { return }
        let muted = readMuted() ?? false
        defer {
            lastVolume = volume
            lastMuted = muted
        }
        let volumeMoved = lastVolume.map { abs($0 - volume) > 0.001 } ?? false
        let muteFlipped = lastMuted.map { $0 != muted } ?? false
        if volumeMoved || muteFlipped {
            onChange?(volume, muted)
        }
    }

    private func readVolume() -> Float? {
        guard AudioObjectHasProperty(device, &Self.volumeAddress) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private func readMuted() -> Bool? {
        guard AudioObjectHasProperty(device, &Self.muteAddress) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted)
        return status == noErr ? muted != 0 : nil
    }

    private static func outputInfo(for device: AudioDeviceID) -> AudioOutputInfo {
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let deviceName = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &size, &name) == noErr
            ? (name?.takeRetainedValue() as String? ?? "Speakers") : "Speakers"

        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &size, &transport)

        switch transport {
        case kAudioDeviceTransportTypeAirPlay:
            return AudioOutputInfo(name: deviceName, symbol: "airplayaudio", isNotable: true)
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return AudioOutputInfo(name: deviceName, symbol: "tv", isNotable: true)
        case kAudioDeviceTransportTypeBuiltIn:
            return AudioOutputInfo(name: deviceName, symbol: "laptopcomputer", isNotable: true)
        case kAudioDeviceTransportTypeUSB:
            return AudioOutputInfo(name: deviceName, symbol: "hifispeaker.fill", isNotable: true)
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            // The Bluetooth alert already covers these, with battery.
            return AudioOutputInfo(name: deviceName, symbol: "headphones", isNotable: false)
        default:
            return AudioOutputInfo(name: deviceName, symbol: "speaker.wave.2.fill", isNotable: false)
        }
    }
}
