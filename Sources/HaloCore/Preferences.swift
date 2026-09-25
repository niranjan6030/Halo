import Foundation

/// How long pop-ups linger. The island's own timings stay in proportion — this
/// stretches or shortens all of them together rather than flattening them to one
/// number, so a volume nudge is still briefer than a download.
public enum AlertPace: String, CaseIterable, Identifiable, Sendable {
    case brief, normal, relaxed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brief: return "Brief"
        case .normal: return "Normal"
        case .relaxed: return "Relaxed"
        }
    }

    public var scale: Double {
        switch self {
        case .brief: return 0.6
        case .normal: return 1
        case .relaxed: return 1.8
        }
    }
}

/// Weather is read from the Mac's locale unless it is told otherwise — handy for
/// anyone whose region and habits disagree.
public enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case automatic, celsius, fahrenheit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Match this Mac"
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    /// `nil` leaves the choice to the locale.
    public var prefersFahrenheit: Bool? {
        switch self {
        case .automatic: return nil
        case .celsius: return false
        case .fahrenheit: return true
        }
    }
}

/// A stretch of the day to stay quiet in, as minutes past midnight.
public struct QuietHours: Equatable, Sendable {
    public var isOn: Bool
    public var from: Int
    public var to: Int

    public init(isOn: Bool, from: Int, to: Int) {
        self.isOn = isOn
        self.from = from
        self.to = to
    }

    public static let defaultFrom = 22 * 60
    public static let defaultTo = 8 * 60

    /// True inside the window. The usual window runs overnight, so it wraps: from
    /// 22:00 to 08:00 means late evening *or* early morning, not the hours between.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn, from != to else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return from < to ? (minute >= from && minute < to) : (minute >= from || minute < to)
    }

    /// "22:00" — the pickers work in whole minutes, shown in the Mac's own format.
    public static func describe(_ minutes: Int, calendar: Calendar = .current) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let date = calendar.date(from: parts) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
