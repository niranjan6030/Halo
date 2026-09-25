import CoreGraphics
import Foundation
import HaloCore
import IOKit.pwr_mgt

/// Recurring reminders, counted in real screen time rather than keystrokes.
///
/// Each reminder keeps its own count of minutes, so any number of them can run at
/// once on their own schedules. A genuine break away from the Mac resets them all,
/// which is the point: an eye break you already took should not be nagged for.
@MainActor
final class WellnessMonitor {
    /// Asked before a reminder is shown. When it says no — the island is hidden behind
    /// a full-screen app, or expanded — the minute is kept rather than spent, so the
    /// reminder arrives at the next opportunity instead of vanishing for a whole cycle.
    var canShow: (() -> Bool)?
    var onReminder: ((Reminder) -> Void)?

    /// Minutes at the screen with no input at all before we assume nobody is there.
    /// Only reached when nothing is holding the display awake, so a film is safe.
    private static let quietMinutesBeforeAway = 10
    /// Minutes away that count as a real break and clear every counter.
    private static let awayMinutesForBreak = 5

    private var timer: Timer?
    private var reminders: [Reminder] = []
    private var quietHours = QuietHours(isOn: false, from: QuietHours.defaultFrom, to: QuietHours.defaultTo)
    /// Screen-time minutes counted per reminder id.
    private var minutes: [UUID: Int] = [:]
    private var awayMinutes = 0

    func update(reminders: [Reminder], quietHours: QuietHours) {
        self.reminders = reminders
        self.quietHours = quietHours
        // Forget counts for reminders that are gone or switched off.
        let live = Set(reminders.filter(\.isOn).map(\.id))
        minutes = minutes.filter { live.contains($0.key) }

        if live.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.minutePassed() }
            }
        }
    }

    private func minutePassed() {
        // Inside quiet hours the counts simply stand still: nothing is shown, and
        // nothing piles up to arrive all at once the moment the window closes.
        guard !quietHours.contains(Date()) else { return }
        guard Self.isAtTheScreen else {
            awayMinutes += 1
            // Long enough away to have rested: start everyone from zero.
            if awayMinutes >= Self.awayMinutesForBreak { minutes.removeAll() }
            return
        }
        awayMinutes = 0

        for reminder in reminders where reminder.isOn {
            let count = (minutes[reminder.id] ?? 0) + 1
            guard count >= reminder.minutes else {
                minutes[reminder.id] = count
                continue
            }
            // Every reminder that comes due is delivered; they used to be checked with
            // an `else if`, so a water reminder falling on the same minute as an eye
            // break was skipped and always slipped a minute late.
            guard canShow?() ?? true else {
                minutes[reminder.id] = count
                continue
            }
            minutes[reminder.id] = 0
            onReminder?(reminder)
        }
    }

    // MARK: Is anybody there?

    /// Screen time as eyes experience it: the display lit, the session unlocked, and
    /// someone plausibly in front of it.
    ///
    /// Input alone is a poor test — reading a long page or watching a film is exactly
    /// when an eye break is worth having, and produces no keystrokes for ages. So a
    /// quiet stretch only counts as away when nothing is holding the display awake,
    /// which is the assertion every video player takes out while it plays.
    private static var isAtTheScreen: Bool {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return false }
        if isLocked { return false }
        if quietSeconds < Double(quietMinutesBeforeAway * 60) { return true }
        return isDisplayHeldAwake
    }

    private static var quietSeconds: Double {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Locked, or switched to another user's session.
    private static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if session["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        return session[kCGSessionOnConsoleKey as String] as? Bool == false
    }

    /// True while some app is keeping the display from sleeping — a video playing,
    /// a presentation, Amphetamine and the like.
    private static var isDisplayHeldAwake: Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let counts = status?.takeRetainedValue() as? [String: Int] else { return false }
        return counts[kIOPMAssertionTypeNoDisplaySleep as String] ?? 0 > 0
            || counts[kIOPMAssertionTypePreventUserIdleDisplaySleep as String] ?? 0 > 0
    }
}
