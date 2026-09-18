import HaloCore
import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let layout = model.layout
        let presentation = model.presentation

        // The island's body and its motion live in IslandBackdrop (Core Animation).
        // This view lays out only what goes inside it, at its final size.
        ZStack(alignment: .top) {
            if RenderMode.isSnapshot {
                IslandSurface(shape: IslandShape(neckWidth: layout.size.width, topRadius: layout.topRadius,
                                                 bottomRadius: layout.bottomRadius),
                              cardAmount: layout.isCard ? 1 : 0, glass: false, notchHeight: model.notchSize.height)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .offset(x: layout.offsetX)
                    .opacity(layout.isVisible ? 1 : 0)
            }

            ZStack(alignment: .top) {
                content(for: presentation, layout: layout)
                    .id(presentation.contentID)
                    .transition(model.pageStep == 0 ? .island : .page(step: model.pageStep))
            }
            .overlay(alignment: .bottom) {
                if case let .expanded(current, _) = presentation, model.isPage(current) {
                    IslandNavigation(model: model, current: current)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.34), value: presentation.contentID)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .overlay {
                if model.isDropTargeted {
                    RoundedRectangle(cornerRadius: layout.bottomRadius, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                        .padding(2)
                }
            }
            .background {
                if case .compact(.siri, _) = presentation {
                    SiriGlow(cornerRadius: layout.bottomRadius)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                }
            }
            .scaleEffect(model.isPressed ? 0.95 : 1, anchor: .top)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: model.isPressed)
            .contentShape(Rectangle())
            .modifier(PressGestures(enabled: !layout.isCard, model: model))
            .simultaneousGesture(swipeUp, including: layout.isCard ? .all : .subviews)
            .modifier(ShelfDropTarget(model: model))
            .offset(x: layout.offsetX)
            .contextMenu {
                Button("Ask Siri") { SiriMonitor.activate() }
                Button("Halo Settings…") { model.openSettings() }
                if model.settings.clipboardHistory {
                    Button("Open Clipboard") { model.openClipboard() }
                }
                Button("Turn Off Halo") { model.settings.isEnabled = false }
                Divider()
                Button("Quit Halo") { NSApp.terminate(nil) }
            }

            if let minimal = presentation.minimal, let diameter = layout.bubbleDiameter {
                MinimalView(activity: minimal, model: model)
                    .frame(width: diameter, height: diameter)
                    .offset(x: layout.offsetX + layout.size.width / 2 + IslandLayout.bubbleGap + diameter / 2)
                    // Splits off the island's edge like iPhone's second activity.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05)),
                        removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)
                            .animation(.easeIn(duration: 0.18))
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Cards have their own buttons, so on them only a clear upward swipe counts.
    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let dy = value.translation.height
                if dy < -24, abs(dy) > abs(value.translation.width) * 1.5 {
                    model.swipeUp()
                }
            }
    }

    @ViewBuilder
    private func content(for presentation: Presentation, layout: IslandLayout) -> some View {
        switch presentation {
        case .idle:
            Color.clear

        case let .compact(activity, _):
            let extents = model.extents(for: activity)
            CompactActivityView(activity: activity, model: model, left: extents.left, right: extents.right,
                                topRadius: layout.topRadius)

        case let .transient(event):
            TransientView(event: event, model: model, layout: layout)

        case let .expanded(content, _):
            switch content {
            case .nowPlaying: NowPlayingExpandedView(model: model, nowPlaying: model.nowPlaying)
            case .call: CallExpandedView(model: model, privacy: model.privacy)
            case .recording: RecordingExpandedView(model: model, privacy: model.privacy)
            case .screenRecording: ScreenRecordingExpandedView(model: model, privacy: model.privacy)
            case .calendar: CalendarExpandedView(model: model, calendar: model.calendar)
            case .controls: ControlsExpandedView(model: model)
            case .weather: WeatherExpandedView(model: model, weather: model.weather)
            case .lyrics: LyricsPageView(model: model, nowPlaying: model.nowPlaying, lyrics: model.lyrics)
            case .shortcuts: ShortcutsPageView(model: model, library: model.shortcuts)
            case .timer: TimerPageView(model: model, timer: model.timer)
            case .system: SystemPageView(model: model, stats: model.stats, fps: model.fps)
            case .reminders: RemindersPageView(model: model, reminders: model.reminders)
            case .notes: NotesPageView(model: model)
            case .mirror: MirrorPageView(model: model)
            case .smartDrop: SmartDropView(model: model)
            }
        }
    }
}

/// Files and images dropped on the island go into the clipboard history.
private struct ShelfDropTarget: ViewModifier {
    @ObservedObject var model: IslandModel

    func body(content: Content) -> some View {
        if RenderMode.isSnapshot {
            content
        } else {
            content.onDrop(of: [.fileURL, .image], isTargeted: Binding(
                get: { model.isDropTargeted },
                set: { model.setDropTargeted($0) }
            )) { providers in
                guard model.settings.clipboardHistory else { return false }
                return model.clipboard.accept(providers: providers) { item in
                    model.dropped(item)
                }
            }
        }
    }
}

/// Click, press-and-hold and swipe-up on the compact island, told apart from one
/// continuous press so none of them get in each other's way.
private struct PressGestures: ViewModifier {
    let enabled: Bool
    let model: IslandModel

    @State private var pressStart: Date?
    @State private var longPressFired = false
    @State private var holdWork: DispatchWorkItem?

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressStart == nil {
                            pressStart = Date()
                            longPressFired = false
                            model.setPressed(true)
                            let work = DispatchWorkItem {
                                longPressFired = true
                                model.setPressed(false)
                                model.longPress()
                            }
                            holdWork = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
                        }
                        // Moving turns a press into a swipe, which is not a hold.
                        if hypot(value.translation.width, value.translation.height) > 8 {
                            holdWork?.cancel()
                            model.setPressed(false)
                        }
                    }
                    .onEnded { value in
                        holdWork?.cancel()
                        holdWork = nil
                        pressStart = nil
                        model.setPressed(false)
                        guard !longPressFired else { return }
                        let dy = value.translation.height
                        if dy < -14, abs(dy) > abs(value.translation.width) {
                            model.swipeUp()
                        } else if hypot(value.translation.width, dy) <= 8 {
                            model.tap()
                        }
                    }
            )
        } else {
            content
        }
    }
}

/// Content either side of the notch, which stays clear for the camera.
struct CompactStrip<Leading: View, Trailing: View>: View {
    let notch: CGSize
    let side: CGFloat
    let topRadius: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.popIn(delay: 0.1).frame(width: side, height: notch.height)
            Spacer(minLength: 0)
            trailing.popIn(delay: 0.16).frame(width: side, height: notch.height)
        }
        .padding(.horizontal, topRadius)
        .frame(height: notch.height)
    }
}

struct CompactActivityView: View {
    let activity: Activity
    @ObservedObject var model: IslandModel
    let left: CGFloat
    let right: CGFloat
    let topRadius: CGFloat

    var body: some View {
        let notch = model.notchSize
        if left == right {
            CompactStrip(notch: notch, side: left, topRadius: topRadius) {
                leading(room: left)
            } trailing: {
                trailing(room: left)
            }
        } else {
            // One side is full: both halves sit together on the side with room.
            let room = max(left, right)
            HStack(spacing: 0) {
                if right > 0 { Spacer(minLength: 0) }
                HStack(spacing: 4) {
                    leading(room: (room - topRadius) / 2).popIn(delay: 0.1)
                    trailing(room: (room - topRadius) / 2).popIn(delay: 0.16)
                }
                // Entirely beside the notch, never under the camera housing.
                .frame(width: max(0, room - topRadius), height: notch.height)
                .padding(right > 0 ? .trailing : .leading, topRadius)
                if left > 0 { Spacer(minLength: 0) }
            }
            .frame(height: notch.height)
        }
    }

    private var small: Bool { left != right }

    @ViewBuilder
    private func leading(room: CGFloat) -> some View {
        let notch = model.notchSize
        switch activity {
        case .nowPlaying:
            ArtworkView(image: model.nowPlaying.artwork, size: min(notch.height - 10, room - (small ? 2 : 10)),
                        cornerRadius: small ? 4 : 6)
        case .call:
            // With little room beside the notch, just the icon.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .semibold))
                    if let call = model.privacy.call {
                        ElapsedText(since: call.started, size: 12)
                    }
                }
                Image(systemName: "phone.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.green)
        case .recording:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    RecordingDot()
                    if let recording = model.privacy.recording {
                        ElapsedText(since: recording.started, size: 12)
                            .foregroundStyle(.red)
                    }
                }
                RecordingDot()
            }
        case .screenRecording:
            Image(systemName: "record.circle")
                .font(.system(size: small ? 12 : 14, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        case .calendar:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                    if let event = model.calendar.next {
                        Text(CalendarFormat.countdown(to: event))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(model.calendar.next?.color ?? .red)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TimerRing(timer: model.timer, date: context.date, size: small ? 13 : 16)
            }
        case .siri:
            SiriLogo(size: min(notch.height - 8, room - 6), listening: model.privacy.microphoneInUse)
        case .download:
            DownloadRing(progress: model.downloadProgress, size: small ? 15 : 18)
        case .privacy:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailing(room: CGFloat) -> some View {
        switch activity {
        case .nowPlaying:
            if model.nowPlaying.track?.isPlaying == true {
                WaveformView(color: model.nowPlaying.accent, isPlaying: true)
                    .frame(width: small ? 13 : 20, height: small ? 11 : 14)
            } else {
                // Paused: a pause glyph, rather than a row of flat bars that
                // looks like dead dots.
                Image(systemName: "pause.fill")
                    .font(.system(size: small ? 10 : 12, weight: .semibold))
                    .foregroundStyle(model.nowPlaying.accent.opacity(0.85))
            }
        case .call:
            WaveformView(color: .green, isPlaying: !model.privacy.microphoneMuted)
                .frame(width: small ? 13 : 20, height: small ? 11 : 14)
        case .recording:
            WaveformView(color: .red, isPlaying: true)
                .frame(width: small ? 13 : 20, height: small ? 11 : 14)
        case .screenRecording:
            if let since = model.privacy.screenRecordingSince {
                ViewThatFits(in: .horizontal) {
                    ElapsedText(since: since, size: 12)
                        .foregroundStyle(.red)
                    RecordingDot(size: 8)
                }
            }
        case .calendar:
            if let event = model.calendar.next, !small {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, 4)
            }
        case .timer:
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let timer = model.timer
                ViewThatFits(in: .horizontal) {
                    Text(timer.kind == .stopwatch ? TimerController.formatElapsed(timer.value(at: context.date))
                                                  : TimerController.format(timer.value(at: context.date)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: timer.isRunning ? "timer" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(timer.isRunning ? Color.orange : Color.white.opacity(0.6))
            }
        case .siri:
            // The logo (leading side) is the identity; this is just a small "it's
            // listening" pulse — showing the same logo twice would look redundant.
            SiriWave(listening: model.privacy.microphoneInUse)
        case .download:
            if let progress = model.downloadProgress {
                Text(progress.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? SystemStats.rate(progress.bytesPerSecond))
                    .font(.system(size: 11.5, weight: .regular).monospacedDigit())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: progress.bytes)
            }
        case .privacy:
            PrivacyDots(privacy: model.privacy)
        }
    }
}

/// The small circle beside the island for a second activity — iPhone's split
/// island when compact, and its "minimal" dot while another one is expanded.
struct MinimalView: View {
    let activity: Activity
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack {
            if RenderMode.isSnapshot {
                Circle().fill(Color.black)
            }
            switch activity {
            case .nowPlaying:
                if let artwork = model.nowPlaying.artwork {
                    ArtworkView(image: artwork, size: 20, cornerRadius: 10)
                } else if model.nowPlaying.track?.isPlaying == true {
                    WaveformView(color: model.nowPlaying.accent, isPlaying: true)
                        .frame(width: 14, height: 11)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.nowPlaying.accent.opacity(0.85))
                }
            case .call:
                Image(systemName: "phone.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            case .calendar:
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.calendar.next?.color ?? .red)
            case .recording, .screenRecording:
                RecordingDot(size: 9)
            case .timer:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TimerRing(timer: model.timer, date: context.date, size: 18)
                }
            case .siri:
                SiriOrb(size: 20, listening: model.privacy.microphoneInUse)
            case .download:
                DownloadRing(progress: model.downloadProgress, size: 18)
            case .privacy:
                PrivacyDots(privacy: model.privacy)
            }
        }
        .contentShape(Circle())
        .onTapGesture { model.tapMinimal() }
    }
}

/// A small ring that empties as a countdown runs (full, and spinning slowly, for the stopwatch).
struct TimerRing: View {
    @ObservedObject var timer: TimerController
    let date: Date
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: timer.kind == .stopwatch ? 1 : 1 - timer.progress(at: date))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer.progress(at: date))
        }
        .frame(width: size, height: size)
    }
}

/// A download arriving: a ring filling to the progress (or spinning when the browser
/// doesn't say how big the file is) around a down arrow.
struct DownloadRing: View {
    let progress: DownloadProgress?
    let size: CGFloat
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.cyan.opacity(0.22), lineWidth: 2.2)
            if let fraction = progress?.fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
                    }
            }
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.cyan)
        }
        .frame(width: size, height: size)
    }
}
