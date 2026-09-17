import AppKit
import HaloCore

@main
@MainActor
enum IslandMain {
    static let delegate = AppDelegate()

    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshots"), arguments.count > flag + 1 {
            Snapshots.render(to: URL(fileURLWithPath: arguments[flag + 1]))
            return
        }
        if let flag = arguments.firstIndex(of: "--pane-icon"), arguments.count > flag + 1 {
            Snapshots.renderPaneIcon(to: URL(fileURLWithPath: arguments[flag + 1]))
            return
        }

        let app = NSApplication.shared
        app.delegate = delegate
        // No Dock icon and no menu bar: the island is the whole interface.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = IslandSettings.shared
    private var controller: IslandController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to the media helper after it has exited must fail softly, not kill Island.
        signal(SIGPIPE, SIG_IGN)

        // Another copy is already running: leave at once. `exit` rather than
        // NSApp.terminate, which can be deferred during launch and leave this copy
        // running with no island at all.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            exit(0)
        }

        controller = IslandController(settings: settings) { [weak self] in self?.showSettings() }

        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            LoginItem.set(true)
            controller?.publishStatus()
            showSettings()
        }
    }

    // Opening Island again (Spotlight, Finder, `open -a Island`) brings up Settings,
    // which is also the way back in after the island has been turned off.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
        }
        settingsWindow?.present()
    }
}
