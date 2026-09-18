import AppKit
import SwiftUI

/// The Island settings screen, laid out like Apple's own System Settings panes.
/// Used both inside System Settings and as the app's fallback window.
public struct SettingsView: View {
    @ObservedObject private var settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text("Halo")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Live activities, alerts and controls that grow out of the notch, the way they do on iPhone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Toggle("Halo", isOn: $settings.isEnabled)
            }

            if settings.context == .pane && !settings.isAppRunning {
                Section {
                    HStack {
                        Label("Halo isn't running", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Start Halo") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Settings.domain) {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                settings.refreshAppRunning()
                                settings.send(command: "requestStatus")
                            }
                        }
                    }
                }
            }

            Group {
                Section {
                    Toggle("Liquid Glass", isOn: $settings.liquidGlass)
                    Toggle("Click to expand", isOn: $settings.clickExpands)
                    Toggle("Expand on hover", isOn: $settings.expandOnHover)
                    Toggle("Haptic feedback", isOn: $settings.haptics)
                    Toggle("Show on displays without a notch", isOn: $settings.showOnDisplaysWithoutNotch)
                    Toggle("Hide in full-screen apps", isOn: $settings.hideInFullScreen)
                    Toggle("Open at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.send(command: "setLaunchAtLogin", value: $0) }
                    ))
                } header: {
                    Text("Behaviour")
                } footer: {
                    Text(settings.clickExpands
                         ? "Click an activity to expand it, press and hold to open its app, and swipe up on the island to dismiss it."
                         : "Click an activity to open its app, like tapping on iPhone. Press and hold to expand it. Swipe up on the island to dismiss.")
                }

                Section {
                    Toggle("Show volume and brightness in the island", isOn: $settings.replaceSystemHUD)
                    if settings.replaceSystemHUD && !settings.accessibilityGranted {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Halo needs Accessibility access to take over the volume and brightness keys.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow…") { settings.send(command: "requestAccessibility") }
                        }
                    }
                } header: {
                    Text("System Pop-ups")
                } footer: {
                    Text("Replaces the macOS volume and brightness pop-ups. Hold Option while pressing a key to open Sound or Display settings as usual.")
                }

                Section {
                    row("Now Playing", "music.note", .pink, $settings.showNowPlaying)
                    row("Calls and recording", "phone.fill", .green, $settings.showCalls)
                    row("Camera and microphone indicators", "record.circle", .green, $settings.showPrivacy)
                    row("Next calendar event", "calendar", .red, $settings.showCalendar)
                    row("Weather", "cloud.sun.fill", .blue, $settings.showWeather)
                    if settings.showWeather {
                        Toggle("Tell me when rain is on the way", isOn: $settings.rainAlerts)
                        TextField("City", text: $settings.weatherCity, prompt: Text("Work it out from this Mac"))
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("Live Activities")
                } footer: {
                    if settings.showWeather {
                        Text("Weather comes from Open-Meteo, which needs no account. Leave the city empty and Halo uses your location, or your time zone's city when macOS won't give it out.")
                    }
                }

                Section("Alerts") {
                    row("Volume", "speaker.wave.2.fill", .gray, $settings.showVolume)
                    row("Brightness", "sun.max.fill", .blue, $settings.showBrightness)
                    row("Charging, low battery and Low Power Mode", "battery.100percent.bolt", .green, $settings.showBattery)
                    row("AirPods and Bluetooth", "airpodspro", .blue, $settings.showBluetooth)
                    row("AirPlay and audio output", "airplayaudio", .indigo, $settings.showAudioOutput)
                    row("Wi-Fi and Personal Hotspot", "wifi", .blue, $settings.showNetwork)
                    row("AirDrop and downloads", "arrow.down.circle.fill", .cyan, $settings.showDownloads)
                    row("Caps Lock", "capslock.fill", .gray, $settings.showCapsLock)
                }

                Section {
                    Picker("First tile", selection: $settings.controlsLeftTile) { tileOptions }
                    Picker("Second tile", selection: $settings.controlsRightTile) { tileOptions }
                    Toggle("Volume slider", isOn: $settings.showVolumeSlider)
                    let buttons = settings.buttons
                    // One picker per button, plus an empty one to add another.
                    ForEach(0..<min(buttons.count + 1, Settings.maximumButtons), id: \.self) { index in
                        Picker(index < buttons.count ? "Button \(index + 1)" : "Add a button", selection: Binding(
                            get: { index < buttons.count ? buttons[index] : .none },
                            set: { settings.setButton($0, at: index) }
                        )) {
                            ForEach(ControlAction.allCases) { action in
                                Label(index < buttons.count && action == .none ? "Remove" : action.title,
                                      systemImage: action.symbol).tag(action)
                            }
                        }
                    }
                    Picker("Clicking the island opens", selection: $settings.idlePage) {
                        ForEach(IdlePage.allCases) { page in
                            Text(page.title).tag(page.rawValue)
                        }
                    }
                } header: {
                    Text("Controls Page")
                } footer: {
                    Text("Pick any two tiles (or None) and up to 12 buttons, six to a row. Choose Remove to take a button away. Focus uses a small shortcut the island helps you make the first time you tap it.")
                }

                Section {
                    ForEach(IslandPage.allCases) { page in
                        row(page.title, page.symbol, pageColor(page), Binding(
                            get: { settings.isPageOn(page) },
                            set: { settings.setPage(page, on: $0) }
                        ))
                    }
                    Toggle("Play a sound when a timer ends", isOn: $settings.timerSound)
                        .disabled(!settings.isPageOn(.timer))
                } header: {
                    Text("Pages")
                } footer: {
                    Text("Each page gets an icon along the bottom of the expanded island; swipe with two fingers to move between them. Lyrics come from LRCLIB, a free lyrics library. Reminders and Mirror ask for access the first time you open them.")
                }

                Section {
                    row("Eye breaks every 20 minutes", "eye.fill", .cyan, $settings.eyeBreaks)
                    row("Drink water every hour", "drop.fill", .blue, $settings.hydrationReminders)
                } header: {
                    Text("Wellbeing")
                } footer: {
                    Text("Gentle reminders in the island, counted only while you're actually using your Mac. An eye break is the 20-20-20 rule: every 20 minutes, look at something 20 feet away for 20 seconds.")
                }

                Section {
                    Toggle("Keep clear of menu bar icons", isOn: $settings.avoidMenuBarIcons)
                    if settings.avoidMenuBarIcons && !settings.accessibilityGranted {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Allow Accessibility so Halo can see where each app's menus end. Until then it stays as narrow as it can.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow…") { settings.send(command: "requestAccessibility") }
                        }
                    }
                } header: {
                    Text("Menu Bar")
                } footer: {
                    Text("Keeps the island narrow enough that it never covers the menu bar icons beside the notch. Short pop-ups like volume can still reach past them for a moment.")
                }

                Section {
                    row("Clipboard history", "doc.on.clipboard.fill", .teal, $settings.clipboardHistory)
                    Toggle("Show in the island when you copy", isOn: $settings.showCopiedInIsland)
                        .disabled(!settings.clipboardHistory)
                    Toggle("Copy screenshots, ready to paste with ⌘V", isOn: $settings.copyScreenshots)
                        .disabled(!settings.clipboardHistory)
                    Toggle("Keep screenshots off the Desktop", isOn: $settings.screenshotsOffDesktop)
                        .disabled(!settings.clipboardHistory)
                } header: {
                    Text("Clipboard")
                } footer: {
                    Text("Press ⌃⌘V anywhere to open your clipboard. It keeps what you copy, the screenshots you take and files you drop on the notch, ready to drag into any app. Screenshots kept off the Desktop are saved in Halo's own folder and cleared after a week. The history is kept in memory only, and anything a password manager marks as private is never recorded.")
                }

            }
            .disabled(!settings.isEnabled)

            Section {
                HStack {
                    Text("Halo runs in the background with no Dock icon.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settings.context == .app {
                        Button("Quit Halo") { NSApp.terminate(nil) }
                    } else if settings.isAppRunning {
                        Button("Quit Halo") {
                            settings.send(command: "quit")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settings.refreshAppRunning() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshAppRunning()
            settings.send(command: "requestStatus")
        }
    }

    @ViewBuilder
    private var tileOptions: some View {
        ForEach(ControlTileKind.allCases) { kind in
            Label(kind.title, systemImage: kind.symbol).tag(kind.rawValue)
        }
    }

    private func pageColor(_ page: IslandPage) -> Color {
        switch page {
        case .lyrics: return .pink
        case .shortcuts: return .indigo
        case .timer: return .orange
        case .system: return .gray
        case .reminders: return .blue
        case .notes: return .yellow
        case .mirror: return .green
        }
    }

    private func row(_ title: String, _ symbol: String, _ color: Color, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                Text(title)
            }
        }
    }

}

/// The Halo wordmark on black, used as the pane's icon art — the same identity as
/// the logo in the README (same rounded weight, same gradient), not a separate
/// glyph invented for Settings.
public struct IslandGlyph: View {
    public init() {}

    static let colors: [Color] = [
        Color(red: 0.25, green: 0.42, blue: 1.0),
        Color(red: 0.55, green: 0.35, blue: 0.98),
        Color(red: 0.93, green: 0.32, blue: 0.68),
        Color(red: 1.0, green: 0.55, blue: 0.25),
    ]

    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    public var body: some View {
        ZStack {
            // The island itself is solid black — the icon's background matches it
            // rather than an invented brand colour.
            tile.fill(Color.black)
            Text("Halo")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing))
        }
        .clipShape(tile)
    }
}
