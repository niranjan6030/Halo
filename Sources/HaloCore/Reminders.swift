import AppKit
import Foundation
import SwiftUI

/// A recurring nudge in the island — the eye break and the glass of water started as
/// two hardcoded ones, and are now just the two that ship switched on by default.
/// Anything the user writes themselves works exactly the same way.
public struct Reminder: Codable, Identifiable, Equatable {
    /// The island's palette, as a name that survives a round trip through defaults.
    public enum Tint: String, Codable, CaseIterable, Identifiable {
        case white, cyan, blue, green, yellow, orange, pink, purple, red
        public var id: String { rawValue }

        public var color: Color {
            switch self {
            case .white: return .white
            case .cyan: return .cyan
            case .blue: return .blue
            case .green: return .green
            case .yellow: return .yellow
            case .orange: return .orange
            case .pink: return .pink
            case .purple: return .purple
            case .red: return .red
            }
        }
    }

    public var id: UUID
    /// What the island says. Kept to a line: it renders beside the notch.
    public var text: String
    /// Any SF Symbol name. `Reminder.symbols` are offered as quick picks, but a name
    /// typed in by hand works too as long as the system actually has that symbol.
    public var symbol: String
    /// How many minutes of actual screen time between showings.
    public var minutes: Int
    /// How long the island holds the nudge. Worth turning up for anything you are
    /// meant to do while it is on screen — twenty seconds of looking into the
    /// distance, say, which is the whole point of the 20-20-20 rule.
    public var seconds: Int
    public var tint: Tint
    /// Weekdays this runs on, numbered the way `Calendar` does: 1 is Sunday.
    /// All seven unless the user narrows it.
    public var days: Set<Int>
    public var isOn: Bool

    public init(id: UUID = UUID(), text: String, symbol: String, minutes: Int,
                seconds: Int = defaultSeconds, tint: Tint = .white,
                days: Set<Int> = everyDay, isOn: Bool) {
        self.id = id
        self.text = text
        self.symbol = symbol
        self.minutes = minutes
        self.seconds = seconds
        self.tint = tint
        self.days = days
        self.isOn = isOn
    }

    /// Older stored reminders predate the colour, and decode as white.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        symbol = try container.decode(String.self, forKey: .symbol)
        minutes = try container.decode(Int.self, forKey: .minutes)
        seconds = try container.decodeIfPresent(Int.self, forKey: .seconds) ?? Self.defaultSeconds
        tint = try container.decodeIfPresent(Tint.self, forKey: .tint) ?? .white
        days = try container.decodeIfPresent(Set<Int>.self, forKey: .days) ?? Self.everyDay
        isOn = try container.decode(Bool.self, forKey: .isOn)
    }

    /// Fixed ids for the two seeded reminders.
    ///
    /// The list is worked out from the old switches every time it is read, right up
    /// until it is first saved. Fresh ids on each read would mean a row could never be
    /// matched back to its reminder, so a toggle would do nothing and an edit would
    /// append a copy instead of replacing the original.
    private static let eyeBreakID = UUID(uuidString: "5F1B0B7C-0E6A-4E2E-9D1E-2E7C0A3F51A1")!
    private static let waterID = UUID(uuidString: "9C3D4A2B-77E1-4F0C-8A55-1D6B9E84C204")!

    /// The 20-20-20 rule, and a glass of water. Seeded for anyone who has never had a
    /// reminder list before, carrying over whether they already had each one on.
    public static func defaults(eyeBreaks: Bool, water: Bool) -> [Reminder] {
        [
            // The eye break holds for its full twenty seconds, so the island itself is
            // the timer you look away from.
            Reminder(id: eyeBreakID, text: "Look 20 feet away for 20 seconds", symbol: "eye.fill",
                     minutes: 20, seconds: 20, tint: .cyan, isOn: eyeBreaks),
            Reminder(id: waterID, text: "Time for a glass of water", symbol: "drop.fill",
                     minutes: 60, tint: .blue, isOn: water),
        ]
    }

    /// Quick picks for the picker. Any other SF Symbol name can be typed in.
    public static let symbols = [
        "eye.fill", "drop.fill", "figure.walk", "figure.flexibility", "cup.and.saucer.fill",
        "pills.fill", "lungs.fill", "heart.fill", "moon.fill", "sun.max.fill",
        "book.fill", "pencil", "phone.fill", "bell.fill", "star.fill", "leaf.fill",
    ]

    public static let minimumMinutes = 1
    public static let maximumMinutes = 480
    public static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    public static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]

    /// Whether this should run at all today.
    public func runs(on date: Date, calendar: Calendar = .current) -> Bool {
        days.isEmpty || days.contains(calendar.component(.weekday, from: date))
    }

    /// "Weekdays", "Weekends", "Mon, Wed, Fri" — or nothing at all when it runs daily.
    public static func daysDescription(_ days: Set<Int>, calendar: Calendar = .current) -> String? {
        if days.isEmpty || days == everyDay { return nil }
        if days == weekdaysOnly { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = calendar.shortWeekdaySymbols
        return days.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            .joined(separator: ", ")
    }

    public static let defaultSeconds = 4
    public static let minimumSeconds = 2
    public static let maximumSeconds = 120

    /// "Every 20 minutes", "Every 2 hours" — how the interval reads in the list.
    public static func intervalDescription(_ minutes: Int) -> String {
        if minutes < 60 { return "Every \(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = "\(hours) hour\(hours == 1 ? "" : "s")"
        return rest == 0 ? "Every \(hourText)" : "Every \(hourText) \(rest) min"
    }

    /// True when macOS actually has this symbol, so a typo falls back to a bell rather
    /// than showing an empty square in the notch.
    public static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// Trimmed, clamped and never empty, whatever was typed into the fields.
    public func sanitised() -> Reminder {
        var copy = self
        copy.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.text.isEmpty { copy.text = "Reminder" }
        let symbolName = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.symbol = Self.symbolExists(symbolName) ? symbolName : "bell.fill"
        copy.minutes = min(Self.maximumMinutes, max(Self.minimumMinutes, minutes))
        copy.seconds = min(Self.maximumSeconds, max(Self.minimumSeconds, seconds))
        // No days at all would mean a reminder that can never run; read it as every day.
        copy.days = days.isEmpty ? Self.everyDay : days.filter { (1...7).contains($0) }
        if copy.days.isEmpty { copy.days = Self.everyDay }
        return copy
    }

    // MARK: Crossing the process boundary

    /// Settings travel between the app and the System Settings pane as single property
    /// list values, so the list rides as one JSON string rather than a new mechanism.
    public static func encode(_ reminders: [Reminder]) -> String {
        guard let data = try? JSONEncoder().encode(reminders) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> [Reminder]? {
        guard let data = json.data(using: .utf8),
              let reminders = try? JSONDecoder().decode([Reminder].self, from: data) else { return nil }
        return reminders
    }
}
