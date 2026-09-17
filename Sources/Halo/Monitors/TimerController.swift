import AppKit

/// A countdown, a stopwatch or a Pomodoro cycle, shown live in the island.
@MainActor
final class TimerController: ObservableObject {
    enum Kind: Equatable {
        case countdown
        case stopwatch
        /// 25 minutes of work then a 5-minute break; every fourth break is 15 minutes.
        case pomodoro(round: Int, isBreak: Bool)
    }

    @Published private(set) var kind: Kind?
    @Published private(set) var isRunning = false
    /// The length of the current countdown or Pomodoro phase.
    @Published private(set) var duration: TimeInterval = 0

    /// While running: when the countdown ends, or when the stopwatch started (minus
    /// time already counted). While paused, `pausedValue` holds the remaining or elapsed time.
    private var anchor = Date()
    private var pausedValue: TimeInterval = 0
    private var ticker: Timer?

    /// Called when a countdown or Pomodoro phase ends, with what to say.
    var onFinish: ((_ message: String, _ symbol: String) -> Void)?

    static let workLength: TimeInterval = 25 * 60
    static let shortBreak: TimeInterval = 5 * 60
    static let longBreak: TimeInterval = 15 * 60

    var isActive: Bool { kind != nil }

    /// Remaining time for countdowns and Pomodoro phases, elapsed time for the stopwatch.
    func value(at date: Date = Date()) -> TimeInterval {
        guard let kind else { return 0 }
        guard isRunning else { return pausedValue }
        switch kind {
        case .stopwatch: return date.timeIntervalSince(anchor)
        case .countdown, .pomodoro: return max(0, anchor.timeIntervalSince(date))
        }
    }

    /// How far through the countdown or phase, 0…1 (0 for the stopwatch).
    func progress(at date: Date = Date()) -> Double {
        guard let kind, kind != .stopwatch, duration > 0 else { return 0 }
        return min(1, max(0, 1 - value(at: date) / duration))
    }

    var title: String {
        switch kind {
        case .countdown: return "Timer"
        case .stopwatch: return "Stopwatch"
        case let .pomodoro(round, isBreak): return isBreak ? "Break" : "Focus \(round) of 4"
        case nil: return "Timer"
        }
    }

    // MARK: Control

    func startCountdown(minutes: Double) {
        begin(.countdown, length: minutes * 60)
    }

    func startStopwatch() {
        kind = .stopwatch
        duration = 0
        anchor = Date()
        isRunning = true
        startTicker()
    }

    func startPomodoro() {
        begin(.pomodoro(round: 1, isBreak: false), length: Self.workLength)
    }

    func pause() {
        guard isRunning else { return }
        pausedValue = value()
        isRunning = false
        stopTicker()
    }

    func resume() {
        guard let kind, !isRunning else { return }
        switch kind {
        case .stopwatch: anchor = Date().addingTimeInterval(-pausedValue)
        case .countdown, .pomodoro: anchor = Date().addingTimeInterval(pausedValue)
        }
        isRunning = true
        startTicker()
    }

    func togglePause() {
        isRunning ? pause() : resume()
    }

    /// Adds a minute to a countdown or Pomodoro phase.
    func addMinute() {
        guard let kind, kind != .stopwatch else { return }
        duration += 60
        if isRunning { anchor = anchor.addingTimeInterval(60) } else { pausedValue += 60 }
    }

    func stop() {
        kind = nil
        isRunning = false
        duration = 0
        pausedValue = 0
        stopTicker()
    }

    private func begin(_ kind: Kind, length: TimeInterval) {
        self.kind = kind
        duration = length
        anchor = Date().addingTimeInterval(length)
        isRunning = true
        startTicker()
    }

    // MARK: Finishing

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isRunning, let kind, kind != .stopwatch, value() <= 0 else { return }
        switch kind {
        case .countdown:
            stop()
            onFinish?("Timer done", "timer")
        case let .pomodoro(round, isBreak):
            if isBreak {
                let next = round >= 4 ? 1 : round + 1
                begin(.pomodoro(round: next, isBreak: false), length: Self.workLength)
                onFinish?("Break's over — focus \(next) of 4", "brain.head.profile")
            } else {
                let long = round >= 4
                begin(.pomodoro(round: round, isBreak: true), length: long ? Self.longBreak : Self.shortBreak)
                onFinish?(long ? "Well done — take 15 minutes" : "Take a 5-minute break", "cup.and.saucer.fill")
            }
        case .stopwatch:
            break
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// The stopwatch shows whole seconds passed, so it rounds down.
    static func formatElapsed(_ seconds: TimeInterval) -> String {
        format(seconds.rounded(.down))
    }
}
