import AppKit
import SwiftUI

/// A field that records the next key press as a shortcut.
struct ShortcutRecorder: View {
    let title: String
    let shortcut: Shortcut
    let fallback: Shortcut
    let set: (Shortcut) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if shortcut != fallback && !recording {
                Button("Reset") { set(fallback) }
                    .buttonStyle(.link)
            }
            Button(recording ? "Press keys…" : shortcut.display) {
                recording ? stop() : start()
            }
            .frame(minWidth: 96)
            .onDisappear(perform: stop)
        }
    }

    private func start() {
        guard !recording else { return }
        recording = true
        // A local monitor, so keys are only taken while this pane is frontmost and the
        // button is waiting — never from the rest of the system.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape backs out and leaves the shortcut alone.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            if let recorded = Shortcut.from(keyCode: event.keyCode,
                                            flags: event.modifierFlags,
                                            characters: event.charactersIgnoringModifiers) {
                set(recorded)
                stop()
            }
            // Swallowed either way, so a half-typed shortcut never reaches the pane.
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Both of Halo's system-wide shortcuts.
struct ShortcutsSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            ShortcutRecorder(title: "Open the island", shortcut: settings.islandShortcut,
                             fallback: .island) { settings.islandShortcut = $0 }
            ShortcutRecorder(title: "Open the clipboard", shortcut: settings.clipboardShortcut,
                             fallback: .clipboard) { settings.clipboardShortcut = $0 }
                .disabled(!settings.clipboardHistory)
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            Text("Click a shortcut and press the keys you want. Escape leaves it as it was. A shortcut another app has already taken cannot be registered, so if one stops working, give it different keys.")
        }
    }
}
