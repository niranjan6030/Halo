import AppKit

/// Detects a full-screen app on the island's display — a video in Brave, a game,
/// Keynote playing — so the island can get out of the way.
///
/// The island's window sits above full-screen windows on purpose (that is what keeps
/// it visible over other apps), so it has to be told to hide.
///
/// Measured on a notched Mac from another app's point of view (which is all Island
/// gets): a full-screen window is the full width and reaches from just under the notch
/// band to the bottom — 1470x923 at y=33 on this display — and belongs to the frontmost
/// app. A zoomed window stops above the Dock (1470x868 here), so the two don't collide.
/// Note that `visibleFrame` still reports the Dock as reserved from outside the
/// full-screen space, so it can't be used for this.
@MainActor
enum FullScreenMonitor {
    static func isFullScreen(on screen: NSScreen) -> Bool {
        let frame = screen.frame
        let visible = screen.visibleFrame
        // The strip at the top a full-screen window stays clear of.
        let notchBand = max(screen.safeAreaInsets.top, frame.maxY - visible.maxY)
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName
        guard let primary = NSScreen.screens.first else { return false }
        // Core Graphics measures from the top-left of the primary display.
        let topEdge = primary.frame.maxY - frame.maxY

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in windows {
            // Layer 0 is a normal app window; menu bars, the Dock and the island are higher.
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String, owner != "Halo",
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { continue }

            guard bounds.width >= frame.width - 2,
                  bounds.height >= frame.height - notchBand - 2,
                  abs(bounds.minX - frame.minX) <= 2,
                  bounds.minY <= topEdge + notchBand + 2 else { continue }
            // The app in full screen is the one you are using; this keeps a zoomed
            // window behind something else from counting.
            guard frontmost == nil || owner == frontmost else { continue }
            return true
        }
        return false
    }
}
