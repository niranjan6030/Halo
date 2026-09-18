import AppKit

/// Follows Siri. macOS gives other apps no Siri API, but Siri becomes the active app
/// while its window is up, so Halo can show Siri in the notch for exactly that long,
/// and open Siri when asked.
///
/// This only catches Siri opened explicitly (menu bar, keyboard shortcut, or Halo's
/// own trigger) — voice-triggered "Hey Siri" shows as a heads-up panel that macOS
/// treats as protected system UI, the same class as Control Centre or a permission
/// dialog: it never becomes the frontmost app, and it doesn't appear in the public
/// window list either (confirmed: CGWindowListCopyWindowInfo reports zero windows
/// owned by Siri even while its panel is visibly on screen). There is no public API
/// this or any third-party app can use to observe it, so "Hey Siri" specifically
/// can't be caught here.
@MainActor
final class SiriMonitor: ObservableObject {
    static let bundleID = "com.apple.Siri"

    @Published private(set) var isActive = false

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if isActive { isActive = false }
    }

    private func update() {
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID
        if active != isActive { isActive = active }
    }

    /// For snapshots and the demo: shows Siri as if it were up.
    func preview(_ active: Bool) {
        isActive = active
    }

    /// Opens Siri, the way its keyboard shortcut or menu bar button does.
    static func activate() {
        let url = URL(fileURLWithPath: "/System/Applications/Siri.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
