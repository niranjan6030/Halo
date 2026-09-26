import AppKit

/// Apps the island should keep out of the way of — a video editor, a game, anything
/// whose own chrome lives under the notch.
///
/// Stored as bundle identifiers so the list survives an app being moved or renamed,
/// and rides between the app and the pane as one JSON string, the way reminders do.
public enum HiddenApps {
    public static func encode(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }

    /// What to call an app in the list. Falls back to the identifier itself when the
    /// app has been deleted, so a stale entry can still be recognised and removed.
    public static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    public static func icon(for id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The bundle identifier of an app the user picked in an open panel.
    public static func identifier(atPath path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }
}
