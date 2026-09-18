import AppKit
import EventKit
import SwiftUI

/// The next thing in your calendar, shown as it approaches — the Mac's answer to
/// iPhone's upcoming-event Live Activity.
@MainActor
final class CalendarMonitor: ObservableObject {
    struct Event: Equatable {
        var title: String
        var start: Date
        var end: Date
        var location: String?
        /// A video call link found in the event, if there is one.
        var joinURL: URL?
        var color: Color

        var isRunning: Bool { start <= Date() && end > Date() }
    }

    /// Shown from this long before it starts until it ends.
    private static let leadTime: TimeInterval = 30 * 60

    @Published private(set) var next: Event?
    @Published private(set) var accessDenied = false
    /// Fired once, right as a marked event's start time arrives — the notch alert.
    var onEventStarting: ((Event) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var isRunning = false
    /// Start time of the last event we already alerted for, so a 30 s refresh tick
    /// doesn't fire the same "starting now" alert repeatedly while it's running.
    private var alertedStart: Date?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.accessDenied = !granted
                guard granted else { return }
                self.refresh()
            }
        }

        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Events tick closer whether or not anything changes.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        next = nil
    }

    func openInCalendar() {
        guard let next else { return }
        // Calendar opens at a date through its own URL scheme.
        let seconds = Int(next.start.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://ekevent/\(seconds)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh() {
        guard isRunning, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 3600),
                                                 end: now.addingTimeInterval(4 * 3600), calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, let end = event.endDate, let start = event.startDate else { return false }
                if event.status == .canceled { return false }
                // Declined invitations are not news.
                if event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) == true {
                    return false
                }
                return end > now && start < now.addingTimeInterval(Self.leadTime)
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }

        let event = upcoming.first.map { event in
            Event(title: event.title ?? "Event",
                  start: event.startDate,
                  end: event.endDate,
                  location: event.location?.isEmpty == false ? event.location : nil,
                  joinURL: Self.meetingLink(in: event),
                  color: event.calendar.map { Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .systemRed) } ?? .red)
        }
        if event != next { next = event }

        // The marked event's start time has arrived: alert once, not on every tick
        // while it keeps being the running event, and not for a meeting that was
        // already well underway when Halo launched (or relaunched) — `alertedStart`
        // starts out nil, so without the recency check the very first refresh during
        // an ongoing meeting would read as "just started" and alert for it again.
        if let event, event.isRunning, event.start != alertedStart, now.timeIntervalSince(event.start) < 35 {
            alertedStart = event.start
            onEventStarting?(event)
        }
    }

    /// Looks for a video call link in the places apps put them.
    private static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, Self.isMeetingLink(url) { return url }
        let haystack = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !haystack.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: haystack, range: NSRange(haystack.startIndex..., in: haystack))
        return matches.compactMap(\.url).first(where: Self.isMeetingLink)
    }

    private static func isMeetingLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com",
                "whereby.com", "meet.jit.si", "facetime.apple.com"].contains { host.contains($0) }
    }
}
