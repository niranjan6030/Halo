import Foundation

/// Keeps new screenshots off the Desktop: macOS saves them into a folder of Island's
/// instead, and they live in Island's clipboard (and on the pasteboard, ready for ⌘V).
/// Turning the setting off puts macOS back to saving on the Desktop.
enum ScreenshotLocation {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Halo/Screenshots", isDirectory: true)

    private static let domain = "com.apple.screencapture" as CFString
    private static let managedKey = "screenshotLocationManaged"
    /// Screenshots Island keeps are cleared out after this long.
    private static let keepFor: TimeInterval = 7 * 24 * 3600

    static func apply(keepOffDesktop: Bool) {
        let current = (CFPreferencesCopyAppValue("location" as CFString, domain) as? String)
            .map { ($0 as NSString).expandingTildeInPath }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        let managed = UserDefaults.standard.bool(forKey: managedKey)

        if keepOffDesktop {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            removeOldScreenshots()
            if current == folder.path {
                UserDefaults.standard.set(true, forKey: managedKey)
                return
            }
            // Island's folder, from before the app was called Halo: move in and take over.
            let legacy = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Island/Screenshots").path
            if current == legacy {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: legacy)) ?? []
                for name in files {
                    try? FileManager.default.moveItem(atPath: legacy + "/" + name, toPath: folder.appendingPathComponent(name).path)
                }
                set(folder.path)
                UserDefaults.standard.set(true, forKey: managedKey)
                return
            }
            // Only take over from the default (the Desktop), never from a folder you chose.
            let isDefault = current == nil || current!.isEmpty || current == desktop
            guard isDefault else { return }
            set(folder.path)
            UserDefaults.standard.set(true, forKey: managedKey)
        } else if managed {
            if current == folder.path { set(nil) }
            UserDefaults.standard.set(false, forKey: managedKey)
        }
    }

    private static func set(_ path: String?) {
        CFPreferencesSetAppValue("location" as CFString, path as CFString?, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func removeOldScreenshots() {
        let keys: [URLResourceKey] = [.creationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let cutoff = Date().addingTimeInterval(-keepFor)
        for file in files {
            if let created = try? file.resourceValues(forKeys: Set(keys)).creationDate, created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
