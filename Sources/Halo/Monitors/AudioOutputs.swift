import AppKit
import CoreAudio

/// The Mac's audio outputs — built-in speakers, headphones, AirPods, displays, AirPlay —
/// and switching between them, the way the Sound menu in Control Center does.
enum AudioOutputs {
    struct Device: Equatable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32

        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                let lower = name.lowercased()
                if lower.contains("airpods max") { return "airpodsmax" }
                if lower.contains("airpods pro") { return "airpodspro" }
                if lower.contains("airpods") { return "airpods" }
                return "headphones"
            case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "tv"
            case kAudioDeviceTransportTypeBuiltIn:
                return name.lowercased().contains("headphone") ? "headphones" : "laptopcomputer"
            case kAudioDeviceTransportTypeUSB: return "hifispeaker"
            default: return "speaker.wave.2"
            }
        }
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    static var current: AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        _ = property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &id)
        return id
    }

    static func devices() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            // Outputs only: devices with output streams.
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var hidden: UInt32 = 0
            if property(id, kAudioDevicePropertyIsHidden, &hidden), hidden != 0 { return nil }
            var name: Unmanaged<CFString>?
            guard property(id, kAudioObjectPropertyName, &name), let label = name?.takeRetainedValue() as String? else { return nil }
            var transport: UInt32 = 0
            _ = property(id, kAudioDevicePropertyTransportType, &transport)
            // Aggregate and virtual devices (screen recorders, meeting apps) aren't places to listen.
            guard transport != kAudioDeviceTransportTypeAggregate, transport != kAudioDeviceTransportTypeVirtual else { return nil }
            return Device(id: id, name: label, transport: transport)
        }
    }

    @discardableResult
    static func select(_ device: Device) -> Bool {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        var output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &output, 0, nil, size, &id)
        var system = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &system, 0, nil, size, &id)
        return status == noErr
    }

    /// A menu of outputs with the current one ticked, shown below the pointer.
    @MainActor
    static func presentMenu(onChange: @escaping (Device) -> Void) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Play Sound Through", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let selected = current
        for device in devices() {
            let item = ClosureMenuItem(title: device.name) {
                if select(device) { onChange(device) }
            }
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == selected ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Sound Settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
