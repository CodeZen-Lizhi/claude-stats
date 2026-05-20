import Foundation

struct LeaderboardRealtimeScope: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let subscriptionPrefix = "leaderboard.score.v1"

    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String

    var id: String { subscriptionID }

    var subscriptionID: String {
        [
            Self.subscriptionPrefix,
            sanitized(metric.rawValue),
            sanitized(period.rawValue),
            sanitized(periodKey),
        ].joined(separator: ".")
    }

    init(metric: LeaderboardMetric, period: LeaderboardPeriod, periodKey: String) {
        self.metric = metric
        self.period = period
        self.periodKey = periodKey
    }

    init?(subscriptionID: String) {
        let components = subscriptionID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 6,
              components[0] == "leaderboard",
              components[1] == "score",
              components[2] == "v1",
              let metric = LeaderboardMetric(rawValue: components[3]),
              let period = LeaderboardPeriod(rawValue: components[4]),
              !components[5].isEmpty else {
            return nil
        }
        self.init(metric: metric, period: period, periodKey: components[5])
    }

    static func liveScope(metric: LeaderboardMetric, period: LeaderboardPeriod, now: Date = .now) -> LeaderboardRealtimeScope {
        let window = LeaderboardPeriodCalculator.window(for: period, now: now)
        return LeaderboardRealtimeScope(metric: metric, period: period, periodKey: window.periodKey)
    }

    static func liveScope(
        metric: LeaderboardMetric,
        period: LeaderboardPeriod,
        requestedWindow: LeaderboardPeriodWindow,
        now: Date = .now
    ) -> LeaderboardRealtimeScope? {
        if period == .allTime {
            return LeaderboardRealtimeScope(metric: metric, period: period, periodKey: requestedWindow.periodKey)
        }

        let currentWindow = LeaderboardPeriodCalculator.window(for: period, now: now)
        guard requestedWindow.periodKey == currentWindow.periodKey else { return nil }
        return LeaderboardRealtimeScope(metric: metric, period: period, periodKey: requestedWindow.periodKey)
    }

    private func sanitized(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        .map(String.init)
        .joined()
    }
}

struct LeaderboardRealtimeNotification: Equatable, Sendable {
    let subscriptionID: String
    let scope: LeaderboardRealtimeScope?
    let receivedAt: Date

    init(subscriptionID: String, receivedAt: Date = .now) {
        self.subscriptionID = subscriptionID
        self.scope = LeaderboardRealtimeScope(subscriptionID: subscriptionID)
        self.receivedAt = receivedAt
    }
}

struct LeaderboardRealtimeState: Codable, Equatable, Sendable {
    var pendingScopes: Set<LeaderboardRealtimeScope>
    var lastNotificationAt: Date?

    static let empty = LeaderboardRealtimeState(pendingScopes: [], lastNotificationAt: nil)
}

enum LeaderboardRealtimeStatus: Equatable, Sendable {
    case inactive
    case live
    case pending
    case historicalCache
    case unavailable(String)

    var displayText: String {
        switch self {
        case .inactive:
            "Ready"
        case .live:
            "Live"
        case .pending:
            "Live pending"
        case .historicalCache:
            "Historical cache"
        case .unavailable:
            "Live unavailable"
        }
    }
}

enum LeaderboardRealtimeDecision: Equatable, Sendable {
    case ignored
    case markedPending(LeaderboardRealtimeScope)
    case refresh(LeaderboardRealtimeScope)
}
