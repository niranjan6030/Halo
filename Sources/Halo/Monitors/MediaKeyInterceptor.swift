import AppKit
import ApplicationServices

/// Takes over the volume and brightness keys so the island replaces the macOS
/// pop-ups. Needs Accessibility permission; without it the keys keep working
/// normally and the island just mirrors the change.
@MainActor
final class MediaKeyInterceptor {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    /// Return true when the key was handled; false passes it on to macOS.
    var handler: ((_ key: Key, _ fineSteps: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose key-down we consumed, so their key-up is consumed too.
    private var swallowed: Set<Int> = []

    var isTrusted: Bool { AXIsProcessTrusted() }
    var isRunning: Bool { tap != nil }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard isTrusted else { return false }

        // NX_SYSDEFINED: the event type media and brightness keys arrive as.
        let mask = CGEventMask(1 << 14)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
        }, userInfo: context) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        swallowed.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let code = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let flags = nsEvent.data1 & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0x0A

        let key: Key
        switch code {
        case 0: key = .volumeUp          // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown        // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute              // NX_KEYTYPE_MUTE
        case 2: key = .brightnessUp      // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown    // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: return Unmanaged.passUnretained(event)
        }

        if !isDown {
            return swallowed.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
        }

        let modifiers = nsEvent.modifierFlags
        // Option alone opens Sound / Displays settings — leave that to macOS.
        if modifiers.contains(.option) && !modifiers.contains(.shift) {
            return Unmanaged.passUnretained(event)
        }
        let fineSteps = modifiers.contains(.option) && modifiers.contains(.shift)

        if handler?(key, fineSteps) == true {
            swallowed.insert(code)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
