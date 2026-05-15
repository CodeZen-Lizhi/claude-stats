import Foundation

enum LeaderboardMetric: String, CaseIterable, Sendable, Identifiable {
    case tokensWithCache
    case tokensWithoutCacheRead
    case activityMinutes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tokensWithCache: "Tokens incl. cache"
        case .tokensWithoutCacheRead: "Tokens excl. cache"
        case .activityMinutes: "Activity minutes"
        }
    }

    var shortLabel: String {
        switch self {
        case .tokensWithCache: "With cache"
        case .tokensWithoutCacheRead: "No cache reads"
        case .activityMinutes: "Activity"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Sendable, Identifiable {
    case day
    case week
    case month
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .allTime: "All-time"
        }
    }
}

struct LeaderboardScore: Sendable, Hashable, Identifiable {
    let id: String
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let score: Int64
    let rank: Int?
    let nickname: String
    let updatedAt: Date
}

struct LeaderboardSubmission: Sendable, Hashable {
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let score: Int64
    let nickname: String
    let periodStartUTC: Date
    let periodEndUTC: Date?
    let appVersion: String
    let updatedAt: Date

    var id: String { "\(metric.rawValue)-\(period.rawValue)-\(periodKey)" }
}

struct LeaderboardPeriodWindow: Sendable, Hashable {
    let period: LeaderboardPeriod
    let periodKey: String
    let startUTC: Date
    let endUTC: Date?

    func contains(_ date: Date) -> Bool {
        date >= startUTC && endUTC.map { date < $0 } ?? true
    }
}

enum LeaderboardPeriodCalculator {
    static func window(for period: LeaderboardPeriod, now: Date = .now) -> LeaderboardPeriodWindow {
        switch period {
        case .day:
            let calendar = utcGregorianCalendar
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let comps = calendar.dateComponents([.year, .month, .day], from: start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0),
                startUTC: start,
                endUTC: end
            )
        case .week:
            let calendar = utcISOCalendar
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
                ?? DateInterval(start: now, duration: 7 * 86_400)
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: interval.start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0),
                startUTC: interval.start,
                endUTC: interval.end
            )
        case .month:
            let calendar = utcGregorianCalendar
            let interval = calendar.dateInterval(of: .month, for: now)
                ?? DateInterval(start: now, duration: 30 * 86_400)
            let comps = calendar.dateComponents([.year, .month], from: interval.start)
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0),
                startUTC: interval.start,
                endUTC: interval.end
            )
        case .allTime:
            return LeaderboardPeriodWindow(
                period: period,
                periodKey: "all",
                startUTC: Date(timeIntervalSince1970: 0),
                endUTC: nil
            )
        }
    }

    static func windows(now: Date = .now) -> [LeaderboardPeriodWindow] {
        LeaderboardPeriod.allCases.map { window(for: $0, now: now) }
    }

    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static var utcISOCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
