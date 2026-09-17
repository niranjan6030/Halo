import EventKit
import Foundation

/// Your unfinished reminders, soonest due first. Access is asked for the first time
/// the Reminders page opens, not at launch.
@MainActor
final class RemindersMonitor: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let listName: String
        let isOverdue: Bool
    }

    enum Access {
        case unknown, granted, denied
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .unknown
        default: return .denied
        }
    }

    /// Asks for access if needed, then loads and keeps the list current.
    func activate() {
        switch Self.currentAccess() {
        case .granted:
            access = .granted
            watch()
            reload()
        case .unknown:
            store.requestFullAccessToReminders { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.access = granted ? .granted : .denied
                    if granted {
                        self.watch()
                        self.reload()
                    }
                }
            }
        case .denied:
            access = .denied
        }
    }

    private func watch() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        guard access == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let now = Date()
            let items = (reminders ?? []).map { reminder -> Item in
                let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                return Item(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled",
                            due: due, listName: reminder.calendar?.title ?? "",
                            isOverdue: due.map { $0 < now } ?? false)
            }
            .sorted { lhs, rhs in
                switch (lhs.due, rhs.due) {
                case let (left?, right?): return left < right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.title < rhs.title
                }
            }
            DispatchQueue.main.async {
                guard let self, self.items != items else { return }
                self.items = items
            }
        }
    }

    @discardableResult
    func complete(_ item: Item) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return false }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            items.removeAll { $0.id == item.id }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func add(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, access == .granted, let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
            reload()
            return true
        } catch {
            return false
        }
    }

    static func due(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
