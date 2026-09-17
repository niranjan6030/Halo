import AppKit
import HaloCore
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: Timer

struct TimerPageView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var timer: TimerController

    private let presets: [Double] = [1, 3, 5, 10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 2)
            if timer.isActive {
                running.appearing(delay: 0.03)
            } else {
                picker.appearing(delay: 0.03)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var picker: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(presets[(row * 5)..<(row * 5 + 5)], id: \.self) { minutes in
                        IslandPill(title: minutes == 60 ? "1 hour" : "\(Int(minutes)) min",
                                   height: 34, expand: true) {
                            timer.startCountdown(minutes: minutes)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                IslandPill(title: "Stopwatch", systemImage: "stopwatch", height: 34, expand: true) {
                    timer.startStopwatch()
                }
                IslandPill(title: "Pomodoro 25 · 5", systemImage: "brain.head.profile", height: 34, expand: true) {
                    timer.startPomodoro()
                }
            }
        }
    }

    private var running: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: timer.kind == .stopwatch ? 1 : timer.progress(at: context.date))
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: symbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 70, height: 70)
                    .padding(.leading, 6)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.isRunning ? timer.title : "\(timer.title) · Paused")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(timer.kind == .stopwatch ? TimerController.formatElapsed(timer.value(at: context.date))
                                                      : TimerController.format(timer.value(at: context.date)))
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 84)

            HStack(spacing: 22) {
                if timer.kind != .stopwatch {
                    RoundAction(symbol: "goforward.60", label: "Add a Minute") { timer.addMinute() }
                }
                RoundAction(symbol: timer.isRunning ? "pause.fill" : "play.fill",
                            label: timer.isRunning ? "Pause" : "Resume") { timer.togglePause() }
                RoundAction(symbol: "xmark", label: "Stop") { timer.stop() }
            }
            .frame(height: IslandModel.controlButtonSize)
        }
    }

    private var tint: Color {
        if case let .pomodoro(_, isBreak) = timer.kind { return isBreak ? .green : .red }
        return .orange
    }

    private var symbol: String {
        switch timer.kind {
        case .stopwatch: return "stopwatch.fill"
        case let .pomodoro(_, isBreak): return isBreak ? "cup.and.saucer.fill" : "brain.head.profile"
        default: return "timer"
        }
    }
}

/// A Controls page tile: the running timer, or a quick 5-minute start.
struct TimerTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var timer: TimerController

    var body: some View {
        Button {
            model.showPage(.timer)
        } label: {
            ControlTile(interactive: true, tint: timer.isActive ? Color.orange.opacity(0.45) : nil) {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(symbol: "timer", tint: .white, title: timer.isActive ? timer.title : "Timer", multicolor: false)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Text(timer.isActive
                             ? (timer.kind == .stopwatch ? TimerController.formatElapsed(timer.value(at: context.date))
                                                         : TimerController.format(timer.value(at: context.date)))
                             : "Start")
                            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Text(timer.isActive ? (timer.isRunning ? "Running" : "Paused") : "Timer, stopwatch, Pomodoro")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: System

struct SystemPageView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var stats: SystemStats
    @ObservedObject var fps: FPSMeter

    var body: some View {
        let snapshot = stats.snapshot
        GlassGroup(spacing: 8) {
            VStack(spacing: 8) {
                Color.clear.frame(height: model.notchSize.height - 2)
                HStack(spacing: 8) {
                    StatTile(symbol: "cpu", title: "CPU", value: "\(Int((snapshot.cpu * 100).rounded()))%",
                             fraction: snapshot.cpu, detail: thermal(snapshot.thermal))
                    StatTile(symbol: "speedometer", title: "FPS", value: "\(fps.fps)",
                             fraction: fps.maximum > 0 ? Double(fps.fps) / Double(fps.maximum) : nil,
                             detail: "\(fps.maximum) Hz", tint: .green)
                    StatTile(symbol: "memorychip", title: "Memory", value: SystemStats.gigabytes(snapshot.memoryUsed),
                             fraction: snapshot.memoryFraction)
                }
                .appearing(delay: 0.03)
                HStack(spacing: 8) {
                    StatTile(symbol: "internaldrive", title: "Storage", value: SystemStats.bytes(snapshot.diskFree),
                             fraction: snapshot.diskUsedFraction, detail: "free")
                    StatTile(symbol: "arrow.up.arrow.down", title: "Network", value: "↓ " + SystemStats.rate(snapshot.download),
                             fraction: nil, caption: "↑ " + SystemStats.rate(snapshot.upload))
                    StatTile(symbol: "heart.fill", title: "Health", value: snapshot.batteryHealth.map { "\($0)%" } ?? "—",
                             fraction: snapshot.batteryHealth.map { Double($0) / 100 }, tint: .green)
                }
                .appearing(delay: 0.08)
                HStack(spacing: 14) {
                    if let cycles = snapshot.cycleCount {
                        footer("arrow.triangle.2.circlepath", "\(cycles) battery cycles")
                    }
                    footer("clock", "Up \(SystemStats.uptime(snapshot.uptime))")
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                                           configuration: NSWorkspace.OpenConfiguration())
                        model.collapse()
                    } label: {
                        Label("Activity Monitor", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 4)
                .appearing(delay: 0.13)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            stats.startWatching()
            fps.startWatching()
        }
        .onDisappear {
            stats.stopWatching()
            fps.stopWatching()
        }
    }

    private func footer(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
    }

    private func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return ""
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double?
    /// A few characters beside the title ("Cool", "60 Hz").
    var detail: String = ""
    /// Shown under the value instead of a bar.
    var caption: String? = nil
    var tint: Color = .white

    var body: some View {
        ControlTile {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    Text(detail)
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                } else {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.16))
                            Capsule()
                                .fill((fraction ?? 0) > 0.85 && tint == .white ? Color.red : tint)
                                .frame(width: geometry.size.width * min(1, max(0, fraction ?? 0)))
                        }
                    }
                    .frame(height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
                }
            }
        }
        .frame(height: 68)
    }
}

/// A Controls page tile with CPU and memory at a glance.
struct SystemTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var stats: SystemStats

    var body: some View {
        Button {
            model.showPage(.system)
        } label: {
            ControlTile(interactive: true) {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(symbol: "cpu", tint: .white, title: "CPU \(Int((stats.snapshot.cpu * 100).rounded()))%", multicolor: false)
                    Spacer(minLength: 0)
                    Text(SystemStats.gigabytes(stats.snapshot.memoryUsed))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("memory used")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(PressableStyle())
        .onAppear { stats.startWatching() }
        .onDisappear { stats.stopWatching() }
    }
}

// MARK: Reminders

struct RemindersPageView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var reminders: RemindersMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: model.notchSize.height - 4)
            HStack {
                Label("Reminders", systemImage: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                if reminders.access == .granted {
                    Text("\(reminders.items.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if reminders.access == .granted {
                    RoundAction(symbol: "plus", label: "New Reminder") {
                        model.editReminder()
                    }
                    .scaleEffect(0.76)
                    .frame(width: 32, height: 32)
                }
            }

            switch reminders.access {
            case .granted:
                if reminders.items.isEmpty {
                    Label("All done", systemImage: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(reminders.items) { item in
                                ReminderRow(item: item) {
                                    if reminders.complete(item) { model.haptic(.levelChange) }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            case .unknown:
                accessPrompt("Halo can show and tick off your reminders.", button: "Allow Access") {
                    reminders.activate()
                }
            case .denied:
                accessPrompt("Reminders access is off for Halo.", button: "Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                    model.collapse()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            if reminders.access == .granted { reminders.activate() }
        }
    }

    private func accessPrompt(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
            IslandPill(title: button, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReminderRow: View {
    let item: RemindersMonitor.Item
    let complete: () -> Void
    @State private var ticked = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { ticked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: complete)
            } label: {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(ticked ? Color.orange : Color.white.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(ticked ? 0.4 : 1))
                    .strikethrough(ticked)
                    .lineLimit(1)
                if let due = item.due {
                    Text(RemindersMonitor.due(due))
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.isOverdue ? Color.red : Color.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            Text(item.listName)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .frame(height: 32)
    }
}

// MARK: Quick note

struct NotesPageView: View {
    @ObservedObject var model: IslandModel
    @AppStorage(QuickNote.key) private var note = ""

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 2)
            Button {
                model.editNote()
            } label: {
                ControlTile(interactive: true) {
                    Text(note.isEmpty ? "Click to jot something down…" : note)
                        .font(.system(size: 13.5, weight: note.isEmpty ? .regular : .medium))
                        .foregroundStyle(.white.opacity(note.isEmpty ? 0.45 : 0.92))
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .buttonStyle(PressableStyle())
            .frame(height: 110)

            HStack(spacing: 8) {
                IslandPill(title: "Edit", systemImage: "pencil", expand: true) { model.editNote() }
                IslandPill(title: "Copy", systemImage: "doc.on.doc", expand: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note, forType: .string)
                    model.collapse()
                    model.show(.success(text: "Note copied"))
                }
                .disabled(note.isEmpty)
                IslandPill(title: "Clear", systemImage: "trash", expand: true) {
                    note = ""
                    model.haptic(.generic)
                }
                .disabled(note.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: Mirror

struct MirrorPageView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: model.notchSize.height - 2)
            MirrorView()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("Only you can see this", systemImage: "lock.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(10)
                }
                .frame(height: 200)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: More tiles

/// The quick note on the Controls page; click to write.
struct NoteTile: View {
    @ObservedObject var model: IslandModel
    @AppStorage(QuickNote.key) private var note = ""

    var body: some View {
        Button {
            model.editNote()
        } label: {
            ControlTile(interactive: true, tint: note.isEmpty ? nil : Color.yellow.opacity(0.28)) {
                VStack(alignment: .leading, spacing: 4) {
                    TileHeader(symbol: "note.text", tint: .yellow, title: "Note", multicolor: false)
                    Text(note.isEmpty ? "Click to write a note" : note)
                        .font(.system(size: 12.5, weight: note.isEmpty ? .regular : .medium))
                        .foregroundStyle(.white.opacity(note.isEmpty ? 0.5 : 0.92))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Today's date, with the next event when calendar events are switched on.
struct DateTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var calendar: CalendarMonitor

    var body: some View {
        TimelineView(.everyMinute) { context in
            ControlTile {
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(context.date.formatted(.dateTime.day()))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(context.date.formatted(.dateTime.month(.abbreviated)))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer(minLength: 0)
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                    Text(calendar.next.map { "\($0.title) · \(CalendarFormat.countdown(to: $0))" } ?? "No upcoming events")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct NetworkTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var stats: SystemStats

    var body: some View {
        Button {
            model.showPage(.system)
        } label: {
            ControlTile(interactive: true) {
                VStack(alignment: .leading, spacing: 2) {
                    TileHeader(symbol: "arrow.up.arrow.down", tint: .white, title: "Network", multicolor: false)
                    Spacer(minLength: 0)
                    Label(SystemStats.rate(stats.snapshot.download), systemImage: "arrow.down")
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Label(SystemStats.rate(stats.snapshot.upload), systemImage: "arrow.up")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                }
                .animation(.snappy, value: stats.snapshot)
            }
        }
        .buttonStyle(PressableStyle())
        .onAppear { stats.startWatching() }
        .onDisappear { stats.stopWatching() }
    }
}

struct StorageTile: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var stats: SystemStats

    var body: some View {
        let snapshot = stats.snapshot
        Button {
            model.clearCaches()
        } label: {
            ControlTile(interactive: true) {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(symbol: "internaldrive", tint: .white, title: "Storage", multicolor: false)
                    Spacer(minLength: 0)
                    Text(SystemStats.bytes(snapshot.diskFree))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule()
                                .fill(snapshot.diskUsedFraction > 0.9 ? Color.red : Color.white)
                                .frame(width: geometry.size.width * snapshot.diskUsedFraction)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 5)
                    Text("free · click to clear caches")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .help("Clear App Caches")
        .onAppear { stats.startWatching() }
        .onDisappear { stats.stopWatching() }
    }
}
