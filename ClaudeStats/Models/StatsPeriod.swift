import Foundation

/// Time windows the Usage screen and menu-bar label can be scoped to.
enum StatsPeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case last7Days
    case last30Days
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }

    /// Inclusive lower bound for "is this activity in the period?", or `nil`
    /// for ``allTime``. Uses the start of the relevant day in the current
    /// calendar.
    func lowerBound(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .allTime:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        }
    }

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lower = lowerBound(now: now, calendar: calendar) else { return true }
        return date >= lower
    }
}
