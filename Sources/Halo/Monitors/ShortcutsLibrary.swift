import Foundation

/// The user's shortcuts from the Shortcuts app, to run from the island.
@MainActor
final class ShortcutsLibrary: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var running: String?

    func refresh() {
        Task.detached(priority: .utility) {
            let output = Self.run(["list"]) ?? ""
            let names = output.split(separator: "\n").map(String.init)
                // Island's own helper isn't something to run by hand.
                .filter { !$0.isEmpty && $0 != FocusController.shortcutName && $0 != FocusController.legacyShortcutName }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.names != names { self.names = names }
                self.isLoaded = true
            }
        }
    }

    func run(_ name: String, completion: @escaping (Bool) -> Void) {
        guard running == nil else { return }
        running = name
        Task.detached(priority: .userInitiated) {
            let worked = Self.run(["run", name]) != nil
            await MainActor.run { [weak self] in
                self?.running = nil
                completion(worked)
            }
        }
    }

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
