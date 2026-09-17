import CoreGraphics
import Foundation

/// Eye-break and water reminders, counted only while someone is using the Mac:
/// time away (no input for five minutes) resets the eye-break count.
@MainActor
final class WellnessMonitor {
    enum Reminder {
        case eyeBreak, water
    }

    var onReminder: ((Reminder) -> Void)?

    private var timer: Timer?
    private var activeMinutesSinceEyeBreak = 0
    private var activeMinutesSinceWater = 0
    private var eyeBreaks = false
    private var water = false

    static let eyeBreakInterval = 20
    static let waterInterval = 60

    func update(eyeBreaks: Bool, water: Bool) {
        self.eyeBreaks = eyeBreaks
        self.water = water
        if eyeBreaks || water {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.minutePassed() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            activeMinutesSinceEyeBreak = 0
            activeMinutesSinceWater = 0
        }
    }

    private func minutePassed() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle > 300 {
            // A proper break away from the screen counts as the eye break.
            activeMinutesSinceEyeBreak = 0
            return
        }
        guard idle < 90 else { return }
        activeMinutesSinceEyeBreak += 1
        activeMinutesSinceWater += 1
        if eyeBreaks, activeMinutesSinceEyeBreak >= Self.eyeBreakInterval {
            activeMinutesSinceEyeBreak = 0
            onReminder?(.eyeBreak)
        } else if water, activeMinutesSinceWater >= Self.waterInterval {
            activeMinutesSinceWater = 0
            onReminder?(.water)
        }
    }
}
