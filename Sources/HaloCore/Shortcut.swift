import AppKit

/// A system-wide keyboard shortcut, stored so it survives a restart and travels
/// between the app and the System Settings pane.
///
/// `modifiers` are Carbon flags, which is what `RegisterEventHotKey` wants. The label
/// is whatever the key produced when it was recorded, so the shortcut can be written
/// out without a key-code-to-character table that would be wrong on other layouts.
public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: Int
    public var modifiers: Int
    public var label: String

    public init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    // Carbon modifier masks.
    public static let command = 256
    public static let shift = 512
    public static let option = 2048
    public static let control = 4096

    public static let island = Shortcut(keyCode: 4, modifiers: control | command, label: "H")
    public static let clipboard = Shortcut(keyCode: 9, modifiers: control | command, label: "V")

    /// "⌃⌘V", in the order macOS writes modifiers.
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + label.uppercased()
    }

    /// A shortcut with no modifier at all would swallow an ordinary key everywhere,
    /// so at least one of Control, Option or Command is required.
    public var isUsable: Bool {
        modifiers & (Self.control | Self.option | Self.command) != 0 && !label.isEmpty
    }

    /// Built from a key press. Returns nil for a press that would not make a safe
    /// shortcut, so the recorder can simply keep listening.
    public static func from(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Shortcut? {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= command }
        if flags.contains(.control) { modifiers |= control }
        if flags.contains(.option) { modifiers |= option }
        if flags.contains(.shift) { modifiers |= shift }
        let label = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcut = Shortcut(keyCode: Int(keyCode), modifiers: modifiers, label: label)
        return shortcut.isUsable ? shortcut : nil
    }

    public static func encode(_ shortcut: Shortcut) -> String {
        guard let data = try? JSONEncoder().encode(shortcut) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String, fallback: Shortcut) -> Shortcut {
        guard let data = json.data(using: .utf8),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              shortcut.isUsable else { return fallback }
        return shortcut
    }
}
