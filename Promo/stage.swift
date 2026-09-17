// A clean backdrop for recording Halo: fills the screen below the menu bar with a soft
// wallpaper so no personal windows appear. Quit with ⌘Q or by killing the process.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.isOpaque = true
let view = NSView(frame: screen.frame)
view.wantsLayer = true
let gradient = CAGradientLayer()
gradient.frame = view.bounds
gradient.colors = [NSColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1).cgColor,
                   NSColor(red: 0.30, green: 0.12, blue: 0.38, alpha: 1).cgColor,
                   NSColor(red: 0.62, green: 0.30, blue: 0.36, alpha: 1).cgColor]
gradient.startPoint = CGPoint(x: 0, y: 1)
gradient.endPoint = CGPoint(x: 1, y: 0)
view.layer?.addSublayer(gradient)
window.contentView = view
window.setFrame(screen.frame, display: true)
window.orderFrontRegardless()
app.run()
