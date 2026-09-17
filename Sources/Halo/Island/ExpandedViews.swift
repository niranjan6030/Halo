import HaloCore
import SwiftUI

/// Space kept clear under the notch in every expanded view.
private struct NotchSpacer: View {
    let model: IslandModel
    var extra: CGFloat = 0

    var body: some View {
        Color.clear.frame(height: model.notchSize.height + extra)
    }
}

// MARK: Now Playing

struct NowPlayingExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        let track = nowPlaying.track
        VStack(spacing: 0) {
            NotchSpacer(model: model, extra: 4)

            HStack(spacing: 14) {
                Button(action: nowPlaying.openSourceApp) {
                    ArtworkView(image: nowPlaying.artwork, size: 62, cornerRadius: 14)
                        .shadow(color: nowPlaying.accent.opacity(0.35), radius: 10, y: 3)
                        .overlay(alignment: .bottomTrailing) {
                            if let icon = nowPlaying.sourceAppIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                    .offset(x: 6, y: 6)
                            }
                        }
                }
                .buttonStyle(PressableStyle())
                .help("Open \(appName(for: track?.bundleID))")

                VStack(alignment: .leading, spacing: 3) {
                    Text(track?.title ?? "Not Playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle(for: track))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                IslandButton(systemName: "airplayaudio", size: 15, diameter: 34, label: "Play Sound Through") {
                    model.setMenuOpen(true)
                    AudioOutputs.presentMenu { _ in }
                    model.setMenuOpen(false)
                }
                IslandButton(systemName: "ellipsis", size: 17, diameter: 34, label: "More") {
                    MusicMenu.present(model: model)
                }
            }
            .frame(height: 66)

            if let track {
                ScrubberView(track: track, accent: nowPlaying.accent) { nowPlaying.seek(to: $0) }
                    .padding(.top, 10)
            }


            HStack(spacing: 38) {
                IslandButton(systemName: "backward.fill", size: 21, diameter: 44, tint: nil, label: "Previous",
                             action: nowPlaying.previous)
                IslandButton(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill",
                             size: 30, diameter: 52, tint: nil, label: track?.isPlaying == true ? "Pause" : "Play",
                             action: nowPlaying.togglePlayPause)
                IslandButton(systemName: "forward.fill", size: 21, diameter: 44, tint: nil, label: "Next",
                             action: nowPlaying.next)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
    }

    private func subtitle(for track: Track?) -> String {
        guard let track else { return "" }
        return [track.artist, track.album].filter { !$0.isEmpty }.first ?? appName(for: track.bundleID)
    }
}

struct ScrubberView: View {
    let track: Track
    let accent: Color
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        if track.duration <= 0 {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(height: 22)
        } else {
            TimelineView(.animation(minimumInterval: 0.25, paused: !track.isPlaying || dragFraction != nil)) { context in
                let position = dragFraction.map { $0 * track.duration } ?? track.position(at: context.date)
                let fraction = position / track.duration

                HStack(spacing: 10) {
                    Text(Clock.elapsed(position))
                        .frame(width: 40, alignment: .trailing)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(dragFraction == nil ? Color.white.opacity(0.9) : accent)
                                .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                        }
                        .frame(height: dragFraction == nil ? 5 : 9)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragFraction = max(0, min(1, value.location.x / geometry.size.width))
                                }
                                .onEnded { value in
                                    let final = max(0, min(1, value.location.x / geometry.size.width))
                                    onSeek(final * track.duration)
                                    dragFraction = nil
                                }
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragFraction == nil)
                    }
                    Text("-" + Clock.elapsed(track.duration - position))
                        .frame(width: 44, alignment: .leading)
                }
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(height: 22)
            }
        }
    }
}

// MARK: Activity cards

/// The shared layout for single-activity cards: icon, title and a big figure on
/// the left, controls on the right.
private struct ActivityCard<Leading: View, Figure: View, Controls: View>: View {
    let model: IslandModel
    let title: String
    let titleColor: Color
    @ViewBuilder var leading: Leading
    @ViewBuilder var figure: Figure
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            NotchSpacer(model: model, extra: 6)
            HStack(spacing: 12) {
                leading
                    .frame(width: 36, height: 36)
                    .padding(.trailing, 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    figure
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) { controls }
            }
            .padding(.horizontal, 26)
            .frame(height: 78)
            Spacer(minLength: 0)
        }
    }
}

// MARK: Calls and recording

struct CallExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var privacy: PrivacyMonitor

    var body: some View {
        if let call = privacy.call {
            ActivityCard(model: model, title: call.name, titleColor: .green) {
                if let icon = call.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "phone.fill").foregroundStyle(.green)
                }
            } figure: {
                ElapsedText(since: call.started, size: 30, weight: .light)
            } controls: {
                IslandButton(systemName: privacy.microphoneMuted ? "mic.slash.fill" : "mic.fill", size: 15, diameter: 42,
                             tint: privacy.microphoneMuted ? .red : .white,
                             label: privacy.microphoneMuted ? "Unmute microphone" : "Mute microphone",
                             action: privacy.toggleMicrophoneMute)
                if privacy.cameraInUse {
                    Image(systemName: "video.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .frame(width: 20)
                }
                IslandButton(systemName: "arrow.up.forward.app.fill", size: 15, diameter: 42, foreground: .white,
                             tint: .green, label: "Open \(call.name)") {
                    call.open()
                    model.collapse()
                }
            }
        }
    }
}

struct RecordingExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var privacy: PrivacyMonitor

    var body: some View {
        if let recording = privacy.recording {
            ActivityCard(model: model, title: "Recording · \(recording.name)", titleColor: .red) {
                RecordingDot(size: 14)
            } figure: {
                ElapsedText(since: recording.started, size: 30, weight: .light)
            } controls: {
                WaveformView(color: .red, isPlaying: true)
                    .frame(width: 30, height: 22)
                IslandButton(systemName: "arrow.up.forward.app.fill", size: 15, diameter: 42, tint: .red,
                             label: "Open \(recording.name)") {
                    recording.open()
                    model.collapse()
                }
            }
        }
    }
}

struct ScreenRecordingExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var privacy: PrivacyMonitor

    var body: some View {
        if let since = privacy.screenRecordingSince {
            ActivityCard(model: model, title: "Screen Recording", titleColor: .red) {
                Image(systemName: "record.circle")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            } figure: {
                ElapsedText(since: since, size: 30, weight: .light)
            } controls: {
                if model.canStopScreenRecording() {
                    IslandPill(title: "Stop", systemImage: "stop.fill", prominent: .red, height: 36) {
                        model.stopScreenRecording?()
                        model.collapse()
                    }
                }
            }
        }
    }
}


// MARK: Controls

/// What the island shows when nothing else is going on, laid out like Control
/// Center: tiles for battery and weather, a volume slider, and a few actions.
struct ControlsExpandedView: View {
    @ObservedObject var model: IslandModel
    @State private var battery: BatteryMonitor.Snapshot?
    @State private var isDraggingVolume = false

    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                Color.clear.frame(height: model.notchSize.height - 2)

                if !model.controlTiles.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(model.controlTiles.enumerated()), id: \.offset) { _, kind in
                            tile(kind)
                        }
                    }
                    .frame(height: 96)
                    .appearing(delay: 0.02)
                }

                if model.settings.showVolumeSlider {
                    ControlSlider(level: Binding(get: { model.volumeLevel },
                                                 set: { model.updateVolume(level: $0, muted: $0 == 0) }),
                                  isDragging: $isDraggingVolume,
                                  symbol: model.volumeMuted || model.volumeLevel == 0 ? "speaker.slash.fill"
                                      : model.volumeLevel < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill") {
                        model.setOutputVolume($0)
                    }
                    .frame(height: 40)
                    .appearing(delay: 0.07)
                }

                if !model.controlButtons.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(model.controlButtonRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 22) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, action in
                                    RoundAction(symbol: symbol(for: action), label: action.title,
                                                isOn: model.isOn(action)) {
                                        model.perform(action)
                                    }
                                }
                            }
                            .frame(height: IslandModel.controlButtonSize)
                        }
                    }
                    .padding(.top, 2)
                    .appearing(delay: 0.12)
                }

                if model.controlTiles.isEmpty && !model.settings.showVolumeSlider && model.controlButtons.isEmpty {
                    Text("Choose tiles and buttons in Settings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(height: 20)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .onAppear(perform: refresh)
        // The volume arrives through the model as it changes; the battery is polled.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    /// One of the two tiles, as chosen in Settings.
    @ViewBuilder
    private func tile(_ kind: ControlTileKind) -> some View {
        switch kind {
        case .focus: FocusTile(model: model, focus: model.focus)
        case .weather: WeatherTile(model: model, weather: model.weather)
        case .nowPlaying: NowPlayingTile(model: model, nowPlaying: model.nowPlaying)
        case .clipboard: clipboardTile
        case .system: SystemTile(model: model, stats: model.stats)
        case .note: NoteTile(model: model)
        case .date: DateTile(model: model, calendar: model.calendar)
        case .network: NetworkTile(model: model, stats: model.stats)
        case .storage: StorageTile(model: model, stats: model.stats)
        case .timer: TimerTile(model: model, timer: model.timer)
        case .battery, .none: batteryTile
        }
    }

    private func symbol(for action: ControlAction) -> String {
        switch action {
        case .focus: return model.focus.isOn ? "moon.fill" : "moon"
        case .mute: return model.volumeMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .desktopIcons: return model.toggles.desktopIconsHidden ? "eye.slash" : "eye"
        case .micMute: return model.toggles.microphoneMuted ? "mic.slash.fill" : "mic.fill"
        case .hiddenFiles: return model.toggles.hiddenFilesShown ? "eye.circle.fill" : "eye.circle"
        case .wifi: return model.toggles.wifiOn ? "wifi" : "wifi.slash"
        default: return action.symbol
        }
    }

    private func refresh() {
        battery = model.batterySnapshot()
        model.focus.refreshInstalled()
        model.toggles.refresh(includeBluetooth: model.controlButtons.contains(.bluetooth))
        if !isDraggingVolume { model.refreshVolume() }
    }

    private var batteryTile: some View {
        ControlTile(tint: battery?.isCharging == true ? Color.green.opacity(0.35) : nil) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(symbol: battery?.isCharging == true ? "bolt.fill" : batterySymbol,
                           tint: batteryColor, title: batteryTitle, multicolor: false)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(battery.map { "\($0.percent)%" } ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text(batteryShortDetail)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(batteryColor == .white ? Color.white : batteryColor)
                            .frame(width: geometry.size.width * CGFloat(battery?.percent ?? 0) / 100)
                    }
                }
                .frame(height: 5)
                .padding(.top, 5)
            }
        }
    }

    /// "2h 28m", "Paused", "Full": the part of the status that fits beside the figure.
    private var batteryShortDetail: String {
        guard let battery else { return "" }
        if let minutes = battery.minutesRemaining {
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        }
        if battery.onAC && !battery.isCharging { return battery.percent >= 95 ? "Full" : "Paused" }
        return ""
    }

    private var clipboardTile: some View {
        Button {
            model.collapse()
            model.openClipboard()
        } label: {
            ControlTile(interactive: true) {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(symbol: "doc.on.clipboard.fill", tint: .white, title: "Clipboard", multicolor: false)
                    Spacer(minLength: 0)
                    Text("\(model.clipboard.items.count)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("items · ⌃⌘V")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var batterySymbol: String {
        switch battery?.percent ?? 100 {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        guard let battery else { return .white }
        if battery.isCharging { return .green }
        if battery.percent <= 20 { return .red }
        return .white
    }

    private var batteryTitle: String {
        guard let battery else { return "Battery" }
        if battery.isCharging { return "Charging" }
        return battery.onAC ? "Plugged In" : "Battery"
    }

    private var batterySubtitle: String {
        guard let battery else { return "Unavailable" }
        guard let minutes = battery.minutesRemaining else {
            if battery.onAC && !battery.isCharging {
                // macOS pauses charging below full to protect the battery.
                return battery.percent >= 95 ? "Fully charged" : "Charging paused"
            }
            return battery.isCharging ? "Calculating…" : "Calculating…"
        }
        let text = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return battery.isCharging ? "\(text) until full" : "\(text) left"
    }
}

/// The rounded panel Control Center modules sit on.
struct ControlTile<Content: View>: View {
    var interactive = false
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassCard(cornerRadius: 22, interactive: interactive, tint: tint)
    }
}

/// The small icon and label at the top of a tile, as in Control Center.
struct TileHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    var multicolor: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(multicolor ? .multicolor : .hierarchical)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }
}

/// A round clear-glass button with a white glyph, like the buttons in Control Center.
struct RoundAction: View {
    let symbol: String
    let label: String
    /// A toggle that's on: white, with a dark glyph, as in Control Center.
    var isOn = false
    let action: () -> Void
    @State private var isHovered = false
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.bounce.down, value: taps)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: IslandModel.controlButtonSize, height: IslandModel.controlButtonSize)
                .contentShape(Circle())
                .scaleEffect(isHovered ? 1.06 : 1)
                .glassCircle(interactive: true, tint: isOn ? Color.white.opacity(0.92) : Color.white.opacity(isHovered ? 0.22 : 0.12))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The current track at a glance; click to open the Now Playing card, or play and pause.
struct NowPlayingTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        Button {
            if nowPlaying.track != nil { model.showPage(.nowPlaying) }
        } label: {
            ControlTile(interactive: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        ArtworkView(image: nowPlaying.artwork, size: 34, cornerRadius: 8)
                        Spacer(minLength: 0)
                        if let track = nowPlaying.track {
                            Button {
                                nowPlaying.togglePlayPause()
                            } label: {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    Spacer(minLength: 0)
                    Text(nowPlaying.track?.title ?? "Not Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(nowPlaying.track?.artist ?? "Music")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Focus at a glance; click to turn Do Not Disturb on or off.
struct FocusTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusController

    var body: some View {
        Button {
            model.toggleFocus()
        } label: {
            ControlTile(interactive: true,
                        tint: focus.isOn ? Color(red: 0.36, green: 0.3, blue: 0.85).opacity(0.85) : nil) {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(symbol: "moon.fill", tint: focus.isOn ? .white : .white.opacity(0.85),
                               title: "Focus", multicolor: false)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if focus.isWorking {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .help(focus.isInstalled ? "Turn Do Not Disturb on or off" : "Set up Focus for the island")
    }

    private var title: String {
        guard focus.isInstalled else { return "Set Up" }
        guard focus.isKnown else { return "Focus" }
        return focus.isOn ? "On" : "Off"
    }

    private var detail: String {
        guard focus.isInstalled else { return "Needs a quick shortcut" }
        if let active = focus.activeFocus { return active }
        return focus.isKnown ? "Click to turn on" : "Click to switch"
    }
}

/// Weather at a glance on the control card; click for the full forecast.
struct WeatherTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var weather: WeatherMonitor

    var body: some View {
        Button {
            model.showPage(.weather)
        } label: {
            ControlTile(interactive: true,
                        tint: weather.conditions.map { WeatherLook.sky($0.code, night: WeatherFormat.isNight()).opacity(0.75) }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(weather.conditions?.place ?? "Weather")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 0)
                    if let conditions = weather.conditions {
                        HStack(alignment: .center, spacing: 0) {
                            Text(WeatherFormat.degrees(conditions.temperature))
                                .font(.system(size: 30, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            Image(systemName: WeatherLook.symbol(conditions.code, night: WeatherFormat.isNight()))
                                .font(.system(size: 26))
                                .symbolRenderingMode(.multicolor)
                        }
                        Text("\(WeatherLook.describe(conditions.code))  H\(WeatherFormat.degrees(conditions.high)) L\(WeatherFormat.degrees(conditions.low))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text(weather.failure ?? "Loading…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// A thick Control Center slider with its icon inside.
struct ControlSlider: View {
    @Binding var level: Float
    @Binding var isDragging: Bool
    let symbol: String
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let fill = CGFloat(min(1, max(0, level))) * geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(geometry.size.height, fill))
                    .opacity(level > 0 ? 1 : 0)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(fill > 38 ? Color.black.opacity(0.75) : Color.white.opacity(0.8))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.leading, 14)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let new = Float(max(0, min(1, value.location.x / geometry.size.width)))
                        level = new
                        onChange(new)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
    }
}

/// A round icon button on the control card, with its name on hover.
struct ControlIcon: View {
    let symbol: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        IslandButton(systemName: symbol, size: 16, diameter: 44, foreground: tint == .white ? .white : tint,
                     tint: .white, label: label, action: action)
    }
}

/// A drag-anywhere volume bar, like the one in Control Centre.
struct VolumeSlider: View {
    @Binding var level: Float
    @Binding var isDragging: Bool
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(6, CGFloat(min(1, max(0, level))) * geometry.size.width))
            }
            .frame(height: isDragging ? 12 : 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let new = Float(max(0, min(1, value.location.x / geometry.size.width)))
                        level = new
                        onChange(new)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 22)
    }
}

/// Small system actions the island can trigger.
enum QuickAction {
    /// Locks the screen the way the Apple menu's "Lock Screen" does. The old
    /// CGSession tool was removed in macOS 26, so this calls login.framework directly
    /// and falls back to putting the display to sleep.
    static func lockScreen() {
        typealias LockScreen = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: LockScreen.self)()
            return
        }
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Every app the user actually has open, excluding Island itself and Finder
    /// (which just relaunches).
    static func quittableApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.bundleIdentifier != "com.apple.finder"
        }
    }

    /// Force quits them all. Unsaved work is lost, so the island asks first.
    @discardableResult
    static func forceQuitAll() -> Int {
        let apps = quittableApps()
        for app in apps { app.forceTerminate() }
        return apps.count
    }

    static func openSystemApp(_ name: String) {
        let url = URL(fileURLWithPath: "/System/Applications/\(name).app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func sleepMac() {
        run("/usr/bin/pmset", ["sleepnow"])
    }

    /// The magnifier from the Digital Color Meter; copies the colour as hex.
    static func pickColor(completion: @escaping (String?) -> Void) {
        NSColorSampler().show { color in
            guard let rgb = color?.usingColorSpace(.sRGB) else {
                completion(nil)
                return
            }
            let hex = String(format: "#%02X%02X%02X",
                             Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()),
                             Int((rgb.blueComponent * 255).rounded()))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            completion(hex)
        }
    }

    /// Ejects every removable or external disk, like dragging them all to the Trash.
    static func ejectAll() async -> (ejected: Int, failed: Int) {
        await Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
            let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
            var ejected = 0
            var failed = 0
            for volume in volumes {
                guard let values = try? volume.resourceValues(forKeys: Set(keys)),
                      values.volumeIsRootFileSystem != true,
                      values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsInternal == false,
                      volume.path.hasPrefix("/Volumes/") else { continue }
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                    ejected += 1
                } catch {
                    failed += 1
                }
            }
            return (ejected, failed)
        }.value
    }

    static func openApp(at path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    /// The Mac's address on the local network (Wi-Fi or Ethernet), IPv4 preferred.
    static func localIPAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr, String(cString: interface.ifa_name).hasPrefix("en"),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if family == UInt8(AF_INET) { return text }
            if fallback == nil, !text.hasPrefix("fe80") { fallback = text }
        }
        return fallback
    }

    /// Apple's own speed test (`networkQuality`), download and upload in megabits per second.
    static func speedTest() async -> (down: Double, up: Double)? {
        await Task.detached(priority: .userInitiated) { () -> (down: Double, up: Double)? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
            process.arguments = ["-c", "-M", "20"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let down = json["dl_throughput"] as? Double else { return nil }
            let up = json["ul_throughput"] as? Double ?? 0
            return (down / 1_000_000, up / 1_000_000)
        }.value
    }

    /// Asks loginwindow for its own Restart or Shut Down dialog, which lets you cancel
    /// and asks apps with unsaved work first.
    static func showPowerDialog(restart: Bool) {
        let event = restart ? "rrst" : "rsdn"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"loginwindow\" to «event aevt\(event)»")?.executeAndReturnError(&error)
        }
    }

    /// Opens the Screenshot toolbar, as ⇧⌘5 does.
    static func takeScreenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func sleepDisplay() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}

// MARK: Calendar

enum CalendarFormat {
    /// "in 12m", "now", "24m left"
    static func countdown(to event: CalendarMonitor.Event) -> String {
        let now = Date()
        if event.isRunning {
            let minutes = Int(event.end.timeIntervalSince(now) / 60)
            return minutes <= 0 ? "now" : "\(minutes)m left"
        }
        let minutes = Int(max(0, event.start.timeIntervalSince(now)) / 60)
        return minutes <= 0 ? "now" : "in \(minutes)m"
    }

    static func range(_ event: CalendarMonitor.Event) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }
}

struct CalendarExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var calendar: CalendarMonitor

    var body: some View {
        if let event = calendar.next {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear.frame(height: model.notchSize.height - 4)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(event.color)
                        .frame(width: 4, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text([CalendarFormat.range(event), event.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 10)) { _ in
                        Text(CalendarFormat.countdown(to: event))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(event.color)
                    }
                }

                HStack(spacing: 8) {
                    if let join = event.joinURL {
                        IslandPill(title: "Join", systemImage: "video.fill", prominent: .green, expand: true) {
                            NSWorkspace.shared.open(join)
                            model.collapse()
                        }
                    }
                    IslandPill(title: "Open in Calendar", systemImage: "calendar", expand: true) {
                        calendar.openInCalendar()
                        model.collapse()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: Weather

/// Formatting shared by the weather row and the weather card.
enum WeatherFormat {
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func hour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Locale.current.measurementSystem == .metric ? "HH" : "ha"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, index: Int) -> String {
        if index == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func isNight(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 6 || hour >= 19
    }
}

/// The line of weather on the control card; click it for the full card.
struct WeatherRow: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var weather: WeatherMonitor

    var body: some View {
        Button {
            model.expand(.weather)
        } label: {
            HStack(spacing: 10) {
                if let conditions = weather.conditions {
                    Image(systemName: WeatherLook.symbol(conditions.code, night: WeatherFormat.isNight()))
                        .font(.system(size: 18))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 26)
                    Text(WeatherFormat.degrees(conditions.temperature))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(WeatherLook.describe(conditions.code))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(conditions.place)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("H \(WeatherFormat.degrees(conditions.high))  L \(WeatherFormat.degrees(conditions.low))")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 26)
                    Text(weather.failure ?? "Getting the weather…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct WeatherExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var weather: WeatherMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 6)

            if let conditions = weather.conditions {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: WeatherLook.symbol(conditions.code, night: WeatherFormat.isNight()))
                        .font(.system(size: 34))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WeatherFormat.degrees(conditions.temperature))
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white)
                        Text("\(WeatherLook.describe(conditions.code)) · \(conditions.place)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("H \(WeatherFormat.degrees(conditions.high))   L \(WeatherFormat.degrees(conditions.low))")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        Text("Feels \(WeatherFormat.degrees(conditions.feelsLike))")
                            .font(.system(size: 11).monospacedDigit())
                        Text("\(conditions.humidity)% · \(Int(conditions.windSpeed.rounded())) \(weather.usesFahrenheit ? "mph" : "km/h")")
                            .font(.system(size: 11).monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }

                if !conditions.hourly.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(conditions.hourly.prefix(7)) { hour in
                            VStack(spacing: 4) {
                                Text(WeatherFormat.hour(hour.time))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.55))
                                Image(systemName: WeatherLook.symbol(hour.code, night: WeatherFormat.isNight(hour.time)))
                                    .font(.system(size: 14))
                                    .symbolRenderingMode(.multicolor)
                                Text(WeatherFormat.degrees(hour.temperature))
                                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 18)
                }

                VStack(spacing: 5) {
                    ForEach(Array(conditions.days.prefix(3).enumerated()), id: \.element.id) { index, day in
                        HStack(spacing: 8) {
                            Text(WeatherFormat.weekday(day.date, index: index))
                                .font(.system(size: 11.5, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(index == 0 ? 0.9 : 0.65))
                                .frame(width: 44, alignment: .leading)
                            Image(systemName: WeatherLook.symbol(day.code))
                                .font(.system(size: 12))
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 20)
                            Spacer(minLength: 0)
                            Text(WeatherFormat.degrees(day.low))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan.opacity(0.7), WeatherLook.tint(day.code)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: 70, height: 4)
                            Text(WeatherFormat.degrees(day.high))
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 18)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: weather.failure == nil ? "cloud.sun.fill" : "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(weather.failure ?? "Getting the weather…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.7))
                    if weather.failure != nil {
                        IslandPill(title: "Try Again", height: 26) { weather.refresh() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }
}
