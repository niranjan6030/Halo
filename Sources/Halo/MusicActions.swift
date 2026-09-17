import AppKit

/// Things the island can do to the current song.
///
/// Apple Music only answers AppleScript, so the library actions (favourite, add to
/// a playlist, reveal) go through it; everything else works with any player.
@MainActor
enum MusicActions {
    static let appleMusicBundleID = "com.apple.Music"

    /// Why the last action failed, when it did.
    enum Failure {
        /// macOS hasn't been told Island may control Music yet.
        case notAllowed
        case other
    }

    private(set) static var lastFailure: Failure = .other

    /// Opens the pane where the user allows Island to control Music.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    static func isAppleMusic(_ bundleID: String?) -> Bool {
        bundleID == appleMusicBundleID
    }

    // MARK: Apple Music

    static func isFavourited() -> Bool? {
        guard let result = run("tell application \"Music\" to get favorited of current track") else { return nil }
        return result == "true"
    }

    @discardableResult
    static func setFavourited(_ favourited: Bool) -> Bool {
        run("tell application \"Music\" to set favorited of current track to \(favourited)") != nil
    }

    static func playlists() -> [String] {
        guard let result = run("""
        tell application "Music"
            set output to ""
            repeat with p in user playlists
                if smart of p is false and special kind of p is none then set output to output & (name of p) & linefeed
            end repeat
            return output
        end tell
        """) else { return [] }
        return result.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    @discardableResult
    static func add(toPlaylist playlist: String) -> Bool {
        run("tell application \"Music\" to duplicate current track to user playlist \"\(escape(playlist))\"") != nil
    }

    @discardableResult
    static func revealInMusic() -> Bool {
        guard run("tell application \"Music\" to reveal current track") != nil else { return false }
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: appleMusicBundleID).map {
            NSWorkspace.shared.openApplication(at: $0, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }

    /// Removes the current song from the Music library. There is no undo from here,
    /// so the menu asks first.
    @discardableResult
    static func deleteFromLibrary() -> Bool {
        run("tell application \"Music\" to delete current track") != nil
    }

    // MARK: Any player

    static func copyToPasteboard(_ track: Track) {
        let text = track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func search(_ track: Track, on service: String) {
        let query = [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let base = service == "YouTube"
            ? "https://www.youtube.com/results?search_query="
            : "https://www.google.com/search?q="
        guard let url = URL(string: base + encoded) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Running AppleScript

    /// Returns the script's result, or nil when it failed (Music not running, no
    /// current track, automation not allowed yet).
    @discardableResult
    private static func run(_ source: String) -> String? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: appleMusicBundleID).first != nil else {
            return nil
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: the user hasn't allowed Island to control Music yet.
            lastFailure = code == -1743 ? .notAllowed : .other
            islandLog.error("music action failed (\(code, privacy: .public)): \(String(describing: error[NSAppleScript.errorMessage]), privacy: .public)")
            return nil
        }
        return result?.stringValue ?? ""
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
