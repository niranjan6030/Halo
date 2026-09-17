import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses the Carbon hot key API, which — unlike watching every key press — needs no
/// Accessibility permission, and only ever sees its own shortcut.
@MainActor
final class GlobalHotKey {
    private static var nextID: UInt32 = 1
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var handlerInstalled = false

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private let id: UInt32
    private var reference: EventHotKeyRef?

    /// `modifiers` uses Carbon flags: cmdKey, controlKey, optionKey, shiftKey.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.action = action
        id = Self.nextID
        Self.nextID += 1
    }

    @discardableResult
    func register() -> Bool {
        guard reference == nil else { return true }
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x49534C44), id: id) // "ISLD"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else {
            reference = nil
            return false
        }
        Self.registry[id] = self
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registry.removeValue(forKey: id)
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.registry[id]?.action() }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
