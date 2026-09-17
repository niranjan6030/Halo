import AppKit
import CoreImage
import SwiftUI

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// Playback position at `timestamp`; the live position is extrapolated from it.
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var isPlaying: Bool
    var bundleID: String?

    func position(at date: Date) -> Double {
        var position = elapsed
        if isPlaying {
            position += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        }
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }
}

/// System-wide now playing (Music, Spotify, browsers, anything that reports to
/// Control Center), read through the IslandMedia helper. See Helper/HaloMedia.m
/// for why this runs inside /usr/bin/perl.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    /// True while playing, and for a short while after pausing — like iPhone, the
    /// island does not vanish the instant you hit pause.
    @Published private(set) var isVisible = false

    private static let pausedLinger: TimeInterval = 30

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var isRunning = false
    private var restartDelay: TimeInterval = 1
    private var lingerWork: DispatchWorkItem?
    /// Ignores the helper's echo of stale state for a moment after a local command.
    private var optimisticUntil = Date.distantPast
    private var artworkGeneration = 0

    private var helperURL: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("libHaloMedia.dylib")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launchHelper()
    }

    func stop() {
        isRunning = false
        lingerWork?.cancel()
        lingerWork = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        buffer.removeAll()
        track = nil
        artwork = nil
        isVisible = false
    }

    /// Used by `Island --snapshots` to render the island without a real player.
    func loadPreview(track: Track, artwork: NSImage?) {
        self.track = track
        self.artwork = artwork
        accent = artwork.flatMap(Self.accentColor(of:)).map(Color.init(nsColor:)) ?? .white
        isVisible = true
    }

    func loadPreviewHidden() {
        isVisible = false
    }

    // MARK: Commands

    func togglePlayPause() {
        guard var current = track else { return }
        current.elapsed = current.position(at: Date())
        current.timestamp = Date()
        current.isPlaying.toggle()
        optimisticUntil = Date().addingTimeInterval(1.2)
        apply(current)
        // Explicit play/pause rather than "toggle": a player that is mid track
        // change can drop a toggle, but it always honours a direct command.
        send(current.isPlaying ? "play" : "pause")
    }

    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to seconds: Double) {
        guard var current = track else { return }
        current.elapsed = seconds
        current.timestamp = Date()
        optimisticUntil = Date().addingTimeInterval(1.2)
        apply(current)
        send("seek \(seconds)")
    }

    func openSourceApp() {
        guard let bundleID = track?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var sourceAppIcon: NSImage? {
        guard let bundleID = track?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func send(_ command: String) {
        guard let input, let data = (command + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    // MARK: Helper process

    private func launchHelper() {
        guard isRunning, let helperURL else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e",
            """
            use DynaLoader;
            my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
            my $s = DynaLoader::dl_find_symbol($h, "island_media_run") or die "missing symbol";
            DynaLoader::dl_install_xsub("main::run", $s);
            run();
            """,
            helperURL.path,
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF: without this the handler would be called again in a tight loop.
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.receive(chunk) }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperExited() }
        }

        do {
            try process.run()
            self.process = process
            self.input = stdinPipe.fileHandleForWriting
        } catch {
            helperExited()
        }
    }

    private func helperExited() {
        process = nil
        input = nil
        buffer.removeAll()
        guard isRunning else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning, self.process == nil else { return }
            self.launchHelper()
        }
    }

    private func receive(_ chunk: Data) {
        guard isRunning, !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                restartDelay = 1
                handle(object)
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "none":
            artworkGeneration += 1
            apply(nil)
            artwork = nil
            accent = .white
        case "info":
            guard let title = message["title"] as? String else { return }
            let timestamp = (message["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            let incoming = Track(
                title: title,
                artist: message["artist"] as? String ?? "",
                album: message["album"] as? String ?? "",
                duration: message["duration"] as? Double ?? 0,
                elapsed: message["elapsed"] as? Double ?? 0,
                timestamp: timestamp,
                rate: message["rate"] as? Double ?? 0,
                isPlaying: message["playing"] as? Bool ?? false,
                bundleID: message["bundle"] as? String
            )
            // Right after a tap the player may still report the old state once.
            if Date() < optimisticUntil, let current = track, current.title == incoming.title,
               current.isPlaying != incoming.isPlaying {
                return
            }
            apply(incoming)
        case "artwork":
            artworkGeneration += 1
            let generation = artworkGeneration
            guard let encoded = message["data"] as? String, let data = Data(base64Encoded: encoded) else {
                artwork = nil
                accent = .white
                return
            }
            Task.detached(priority: .utility) {
                let image = NSImage(data: data)
                let color = image.flatMap(Self.accentColor(of:))
                await MainActor.run { [weak self] in
                    // A newer artwork (or "nothing playing") may have arrived meanwhile.
                    guard let self, self.artworkGeneration == generation else { return }
                    self.artwork = image
                    self.accent = color.map(Color.init(nsColor:)) ?? .white
                }
            }
        default:
            break
        }
    }

    private func apply(_ newTrack: Track?) {
        if track != newTrack { track = newTrack }

        guard let newTrack else {
            lingerWork?.cancel()
            lingerWork = nil
            isVisible = false
            return
        }
        if newTrack.isPlaying {
            lingerWork?.cancel()
            lingerWork = nil
            if !isVisible { isVisible = true }
        } else if isVisible, lingerWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lingerWork = nil
                if self.track?.isPlaying != true { self.isVisible = false }
            }
            lingerWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausedLinger, execute: work)
        }
    }

    /// The artwork's average colour, lifted so it stays readable on black.
    nonisolated static func accentColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.12 { return NSColor(white: 0.92, alpha: 1) }
        return NSColor(hue: hue, saturation: min(1, saturation * 1.25), brightness: max(brightness, 0.82), alpha: 1)
    }
}
