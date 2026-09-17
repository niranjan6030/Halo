import AppKit

/// Turns Focus (Do Not Disturb) on and off from the island.
///
/// macOS gives apps no way to read or change Focus directly — its database needs Full
/// Disk Access — but Shortcuts can do both. Island runs one shortcut, "Island Focus",
/// that toggles Do Not Disturb and then reports the current Focus, which tells Island
/// whether it ended up on or off.
@MainActor
final class FocusController: ObservableObject {
    nonisolated static let shortcutName = "Halo Focus"
    /// The name from before the app was called Halo; still used if that's what's installed.
    nonisolated static let legacyShortcutName = "Island Focus"
    /// Whichever of the two names is installed.
    private var installedName = shortcutName

    /// Whether the shortcut exists yet; until it does, the tile offers to set it up.
    @Published private(set) var isInstalled = false
    /// The Focus as of Island's last toggle: its name while on, nil while off.
    @Published private(set) var activeFocus: String?
    @Published private(set) var isKnown = false
    @Published private(set) var isWorking = false

    var isOn: Bool { activeFocus != nil }

    private let defaults = UserDefaults.standard

    init() {
        if defaults.object(forKey: "focus.known") != nil {
            isKnown = true
            activeFocus = defaults.string(forKey: "focus.active")
        }
    }

    /// Checks whether the shortcut has been added. Cheap enough to call when the card opens.
    func refreshInstalled() {
        Task.detached(priority: .utility) {
            let names = Self.run(["list"])?.split(separator: "\n").map(String.init) ?? []
            let name = names.contains(Self.shortcutName) ? Self.shortcutName
                : (names.contains(Self.legacyShortcutName) ? Self.legacyShortcutName : nil)
            await MainActor.run { [weak self] in
                self?.isInstalled = name != nil
                if let name { self?.installedName = name }
            }
        }
    }

    /// Toggles Do Not Disturb. Returns through `completion` with a message to show.
    func toggle(completion: @escaping (_ text: String, _ success: Bool) -> Void) {
        guard isInstalled else {
            showSetup()
            return
        }
        guard !isWorking else { return }
        isWorking = true
        let name = installedName
        Task.detached(priority: .userInitiated) {
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("halo-focus.txt")
            try? FileManager.default.removeItem(at: output)
            let result = Self.run(["run", name, "--output-path", output.path,
                                   "--output-type", "public.plain-text"])
            let focus = (try? String(contentsOf: output, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWorking = false
                guard result != nil else {
                    completion("Couldn't run the \(name) shortcut", false)
                    return
                }
                let active = (focus?.isEmpty ?? true) ? nil : focus
                self.activeFocus = active
                self.isKnown = true
                self.defaults.set(true, forKey: "focus.known")
                self.defaults.set(active, forKey: "focus.active")
                completion(active.map { "\($0) on" } ?? "Focus off", true)
            }
        }
    }

    /// Walks through making the shortcut, which takes about half a minute, once.
    func showSetup() {
        let alert = NSAlert()
        alert.messageText = "Set up Focus for the island"
        alert.informativeText = """
        macOS only lets Shortcuts change Focus, so the island needs one small shortcut:

        1.  In Shortcuts, make a new shortcut named “\(Self.shortcutName)”.
        2.  Add the action “Set Focus”, and set it to Toggle Do Not Disturb.
        3.  Add the action “Get Current Focus” after it.

        Then tap the Focus tile again.
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Runs the `shortcuts` command; nil when it fails.
    private nonisolated static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
