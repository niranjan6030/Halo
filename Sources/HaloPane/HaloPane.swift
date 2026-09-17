import HaloCore
import PreferencePanes
import SwiftUI

/// The Halo page inside System Settings.
@objc(HaloPreferencePane)
final class HaloPreferencePane: NSPreferencePane {
    @MainActor
    override func loadMainView() -> NSView {
        let view = NSHostingView(rootView: SettingsView(settings: .shared))
        view.frame = NSRect(x: 0, y: 0, width: 668, height: 900)
        view.autoresizingMask = [.width, .height]
        mainView = view
        return view
    }

    override func didSelect() {
        MainActor.assumeIsolated {
            Settings.shared.refreshAppRunning()
            Settings.shared.send(command: "requestStatus")
        }
    }
}
