import AppKit
import HaloCore
import SwiftUI

/// Island's settings live in System Settings (Halo.prefPane). This window is
/// the fallback for when the pane isn't installed.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    static var paneURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/PreferencePanes/Halo.prefPane", isDirectory: true)
    }

    init(settings: IslandSettings) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Halo"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.center()
    }

    /// Opens Island's page in System Settings, or this window if the page is missing.
    func present() {
        if FileManager.default.fileExists(atPath: Self.paneURL.path), NSWorkspace.shared.open(Self.paneURL) {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
