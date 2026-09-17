import AppKit

struct DownloadInfo: Equatable {
    var url: URL
    var isAirDrop: Bool

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// A download still arriving: from Safari, Chrome, Firefox or another browser.
struct DownloadProgress: Equatable {
    var name: String
    var bytes: Int64
    /// Known for Safari, which records the full size; browsers that don't show speed only.
    var total: Int64?
    var bytesPerSecond: Double
    /// Other downloads running at the same time.
    var others: Int

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(bytes) / Double(total))
    }
}

/// Reports files that finish arriving in ~/Downloads, including AirDrop transfers, and
/// follows downloads while they're still coming in.
@MainActor
final class DownloadsMonitor {
    var onFinished: ((DownloadInfo) -> Void)?
    var onProgress: ((DownloadProgress?) -> Void)?
    private var lastSizes: [String: (bytes: Int64, at: Date)] = [:]
    private var lastProgress: DownloadProgress?

    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    /// New files wait here until their size stops changing.
    private var settling: [String: (size: Int64, checks: Int)] = [:]
    private var settleTimer: Timer?

    /// Partial files browsers and macOS use while a download is still running.
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]

    func start() {
        guard source == nil else { return }
        known = Set(currentNames())

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source

        settleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSettling() }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        settleTimer?.invalidate()
        settleTimer = nil
        settling.removeAll()
        if lastProgress != nil {
            lastProgress = nil
            onProgress?(nil)
        }
    }

    private func currentNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { !$0.hasPrefix(".") } ?? []
    }

    private func scan() {
        let names = Set(currentNames())
        for name in names.subtracting(known) {
            let ext = (name as NSString).pathExtension.lowercased()
            if !Self.partialExtensions.contains(ext) {
                settling[name] = (-1, 0)
            }
        }
        known = names
    }

    /// Partial downloads in the folder, with their size so far.
    private func trackProgress() {
        let now = Date()
        var running: [(name: String, bytes: Int64, total: Int64?, speed: Double)] = []
        for name in currentNames() {
            let ext = (name as NSString).pathExtension.lowercased()
            guard Self.partialExtensions.contains(ext), ext != "tmp" else { continue }
            let url = folder.appendingPathComponent(name)
            var bytes: Int64 = 0
            var total: Int64?
            var display = (name as NSString).deletingPathExtension
            if ext == "download" {
                // Safari keeps an Info.plist beside the partial file with the full size.
                if let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
                    bytes = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                    if let path = info["DownloadEntryPath"] as? String { display = (path as NSString).lastPathComponent }
                }
                if bytes == 0 { bytes = Self.folderSize(url) }
            } else {
                bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
            }
            if display.hasPrefix("Unconfirmed ") { display = "Download" }
            var speed = 0.0
            if let last = lastSizes[name], now.timeIntervalSince(last.at) > 0.2, bytes >= last.bytes {
                speed = Double(bytes - last.bytes) / now.timeIntervalSince(last.at)
            }
            lastSizes[name] = (bytes, now)
            running.append((display, bytes, total.flatMap { $0 > 0 ? $0 : nil }, speed))
        }
        lastSizes = lastSizes.filter { entry in running.contains { $0.name == entry.key } || currentNames().contains(entry.key) }

        let progress: DownloadProgress?
        if let biggest = running.max(by: { $0.bytes < $1.bytes }) {
            // Keep the speed steady rather than jumping every second.
            let previous = lastProgress?.name == biggest.name ? lastProgress?.bytesPerSecond ?? biggest.speed : biggest.speed
            progress = DownloadProgress(name: biggest.name, bytes: biggest.bytes, total: biggest.total,
                                        bytesPerSecond: previous * 0.5 + biggest.speed * 0.5, others: running.count - 1)
        } else {
            progress = nil
        }
        if progress != lastProgress {
            lastProgress = progress
            onProgress?(progress)
        }
    }

    private static func folderSize(_ url: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func checkSettling() {
        trackProgress()
        for (name, state) in settling {
            let url = folder.appendingPathComponent(name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                settling.removeValue(forKey: name)
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if size == state.size && size > 0 {
                settling.removeValue(forKey: name)
                onFinished?(DownloadInfo(url: url, isAirDrop: Self.cameFromAirDrop(url)))
            } else if state.checks > 600 {
                settling.removeValue(forKey: name)
            } else {
                settling[name] = (size, state.checks + 1)
            }
        }
    }

    /// AirDrop stamps received files' quarantine record with sharingd, the AirDrop daemon.
    private static func cameFromAirDrop(_ url: URL) -> Bool {
        let length = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0)
        guard length > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, "com.apple.quarantine", &buffer, length, 0, 0) == length else { return false }
        return String(decoding: buffer, as: UTF8.self).localizedCaseInsensitiveContains("sharingd")
    }
}
