import AppKit
import HaloCore
import SwiftUI

/// `Island --snapshots <dir>` renders every island state to PNGs and exits, so the
/// layout can be checked without watching the notch.
@MainActor
enum Snapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        RenderMode.isSnapshot = true

        func make() -> IslandModel {
            let model = IslandModel(settings: IslandSettings.shared, nowPlaying: NowPlayingMonitor(),
                                    calendar: CalendarMonitor(), weather: WeatherMonitor(),
                                    privacy: PrivacyMonitor(), clipboard: ClipboardHistory(), openSettings: {})
            model.updateNotch(size: CGSize(width: 185, height: 32), hasNotch: true)
            return model
        }

        let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        let track = Track(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", duration: 200,
                          elapsed: 74, timestamp: Date(), rate: 1, isPlaying: true, bundleID: "com.apple.Music")

        var states: [(String, (IslandModel) -> Void)] = [
            ("01-idle", { _ in }),
            ("02-compact-music", { $0.nowPlaying.loadPreview(track: track, artwork: artwork) }),
            ("03-expanded-music", {
                $0.nowPlaying.loadPreview(track: track, artwork: artwork)
                $0.expand(.nowPlaying)
            }),
            ("08-volume", { $0.show(.volume(level: 0.6, muted: false)) }),
            ("09-brightness", { $0.show(.brightness(level: 0.3)) }),
            ("10-charging", { $0.show(.charging(percent: 78)) }),
            ("11-airpods", {
                $0.show(.bluetoothConnected(BluetoothDeviceInfo(name: "AirPods Pro", symbol: "airpodspro",
                                                                batteryLeft: 84, batteryRight: 80)))
            }),
            ("12-low-battery", { $0.show(.lowBattery(percent: 10)) }),
        ]
        states.append(("16-drop-target", { $0.show(.dropTarget) }))
        states.append(("22-controls", { $0.expand(.controls) }))
        states.append(("23-weather", { $0.expand(.weather) }))
        states.append(("24-timer", { $0.expand(.timer) }))
        states.append(("25-timer-running", { $0.timer.startPomodoro(); $0.expand(.timer) }))
        states.append(("26-system", { $0.expand(.system) }))
        states.append(("27-notes", { $0.expand(.notes) }))
        states.append(("30-unplugged", { $0.show(.unplugged(percent: 58)) }))
        states.append(("31-compact-menus-left", {
            $0.nowPlaying.loadPreview(track: track, artwork: artwork)
            $0.updateMenuBarRoom(.init(left: 0, right: 37))
        }))
        states.append(("29-reminders", { $0.expand(.reminders) }))
        states.append(("17-network-hotspot", { $0.show(.network(.hotspot)) }))
        states.append(("18-caps-lock", { $0.show(.capsLock(on: true)) }))
        states.append(("19-airplay", {
            $0.show(.audioOutput(AudioOutputInfo(name: "Living Room TV", symbol: "airplayaudio", isNotable: true)))
        }))
        states.append(("20-download", {
            $0.show(.download(DownloadInfo(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), isAirDrop: true)))
        }))

        for (name, setUp) in states {
            let model = make()
            setUp(model)
            let extent = model.maximumExtent
            let view = IslandView(model: model)
                .frame(width: extent.width + 80, height: extent.height + 40)
                .background(Color(red: 0.36, green: 0.42, blue: 0.55))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }

    /// The icon System Settings shows beside "Halo" in its sidebar.
    static func renderPaneIcon(to url: URL) {
        let renderer = ImageRenderer(content: IslandGlyph().frame(width: 64, height: 64))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
