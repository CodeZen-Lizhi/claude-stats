import Foundation

struct OpenAIStatusUptimeSnapshot: Sendable, Codable, Equatable {
    let histories: [String: OpenAIStatusUptimeHistory]
    let groupDefinitions: [OpenAIStatusGroupDefinition]
    let fetchedAt: Date

    func history(for group: OpenAIStatusGroup) -> OpenAIStatusUptimeHistory? {
        histories[group.id]
            ?? histories.values.first { $0.groupName == group.name }
    }
}

struct OpenAIStatusUptimeHistory: Identifiable, Sendable, Codable, Equatable {
    let groupID: String
    let groupName: String
    let startDate: Date?
    let days: [OpenAIStatusUptimeDay]
    let sourceUptimePercent: Double?

    var id: String { groupID }

    func recentDays(count: Int = OpenAIStatusUptimeWindow.dayCount) -> [OpenAIStatusUptimeDay] {
        guard days.count > count else { return days }
        return Array(days.suffix(count))
    }

    func uptimePercent(recentDayCount: Int = OpenAIStatusUptimeWindow.dayCount) -> Double? {
        if let sourceUptimePercent {
            return sourceUptimePercent
        }

        let window = recentDays(count: recentDayCount)
        let validDays = window.filter { day in
            guard let startDate else { return true }
            return day.date >= startDate
        }
        guard !validDays.isEmpty else { return nil }

        let totalSeconds = validDays.count * OpenAIStatusUptimeWindow.secondsPerDay
        let downtimeSeconds = validDays.reduce(0) { total, day in
            total + min(OpenAIStatusUptimeWindow.secondsPerDay, day.outageSeconds)
        }
        guard totalSeconds > 0 else { return nil }

        let uptimeRatio = 1 - (Double(downtimeSeconds) / Double(totalSeconds))
        return max(0, min(1, uptimeRatio)) * 100
    }
}

struct OpenAIStatusUptimeDay: Identifiable, Sendable, Codable, Equatable {
    let date: Date
    let degradedPerformanceSeconds: Int
    let partialOutageSeconds: Int
    let fullOutageSeconds: Int
    let relatedEvents: [OpenAIStatusUptimeEvent]

    var id: Date { date }

    var outageSeconds: Int {
        degradedPerformanceSeconds + partialOutageSeconds + fullOutageSeconds
    }

    var hasOutage: Bool {
        outageSeconds > 0
    }
}

struct OpenAIStatusUptimeEvent: Sendable, Codable, Equatable {
    let name: String
    let code: String
    let permalink: URL?
}

enum OpenAIStatusUptimeWindow {
    static let dayCount = 90
    static let secondsPerDay = 24 * 60 * 60
}

struct OpenAIStatusUptimeRow: Identifiable, Sendable, Equatable {
    let group: OpenAIStatusGroup
    let history: OpenAIStatusUptimeHistory?

    var id: String { group.id }
}
