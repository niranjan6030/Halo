import AppKit

/// Clears app caches to free up storage.
///
/// Only your own ~/Library/Caches: files apps keep to load faster and rebuild on
/// their own. Nothing personal lives there, and system caches (which would need an
/// administrator password) are left alone. Caches belonging to apps that are open
/// right now are skipped, since deleting them underneath a running app can upset it.
enum CacheCleaner {
    struct Plan {
        var folders: [URL]
        var bytes: Int64
        var skippedApps: [String]
    }

    /// Folders that live in Caches but aren't safe to throw away: macOS services that
    /// run without showing as apps, and tool downloads you'd have to reinstall by hand.
    private static let keep: [String] = [
        "com.apple.", "CloudKit", "GeoServices", "FamilyCircle", "familycircled", "Metadata",
        "SiriTTS", "PassKit", "icloudmailagent", "askpermissiond", "Animoji", "GameKit", "PHTPhenotype",
        "CCTClearcutLogger", "ms-playwright",
    ]

    private static var cachesFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
    }

    /// Works out what would be cleared. Reads the disk, so call it off the main thread.
    static func plan(runningBundleIDs: Set<String>, runningNames: [String: String]) -> Plan {
        // Many apps file their caches under the company rather than the app:
        // Chrome uses "Google", Brave "BraveSoftware", Adobe apps "Adobe".
        var vendors: [String: String] = [:]
        for id in runningBundleIDs {
            let parts = id.split(separator: ".")
            guard parts.count >= 2, parts[1].count >= 3 else { continue }
            vendors[parts[1].lowercased()] = runningNames[id] ?? id
        }
        // ...or after the app's own name (e.g. a helper process named after its parent app).
        var appWords: [String: String] = [:]
        for name in runningNames.values {
            let word = name.split(separator: " ").first.map { $0.lowercased() } ?? ""
            if word.count >= 5, !["system", "apple", "macos"].contains(word) { appWords[word] = name }
        }

        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: cachesFolder, includingPropertiesForKeys: nil) else {
            return Plan(folders: [], bytes: 0, skippedApps: [])
        }
        var folders: [URL] = []
        var bytes: Int64 = 0
        var skipped: Set<String> = []
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if keep.contains(where: { name.hasPrefix($0) }) { continue }
            // A running app's cache folder is named after its bundle identifier.
            if let match = runningBundleIDs.first(where: { name == $0 || name.hasPrefix($0 + ".") }) {
                skipped.insert(runningNames[match] ?? match)
                continue
            }
            // ...or after its company, which could belong to any of that company's open apps.
            let lowered = name.lowercased()
            if let vendor = vendors.first(where: { lowered.contains($0.key) }) {
                skipped.insert(vendor.value)
                continue
            }
            if let app = appWords.first(where: { lowered.contains($0.key) }) {
                skipped.insert(app.value)
                continue
            }
            let size = allocatedSize(of: entry)
            guard size > 0 else { continue }
            folders.append(entry)
            bytes += size
        }
        return Plan(folders: folders, bytes: bytes, skippedApps: skipped.sorted())
    }

    /// Deletes what the plan found. Returns the bytes actually freed; folders macOS
    /// protects are skipped quietly.
    static func clear(_ plan: Plan) -> Int64 {
        var freed: Int64 = 0
        for folder in plan.folders {
            let before = allocatedSize(of: folder)
            try? FileManager.default.removeItem(at: folder)
            let after = FileManager.default.fileExists(atPath: folder.path) ? allocatedSize(of: folder) : 0
            freed += max(0, before - after)
        }
        return freed
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                              options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
