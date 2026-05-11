import Foundation

/// Aggregate usage across many sessions, scoped to a ``StatsPeriod``.
struct UsageSummary: Sendable, Hashable {
    let period: StatsPeriod
    let sessionCount: Int
    let models: [ModelUsage]
    let daily: [DaySlice]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { models.reduce(0) { $0 + $1.estimatedCost } }
    var messageCount: Int { models.reduce(0) { $0 + $1.messageCount } }

    static func empty(period: StatsPeriod) -> UsageSummary {
        UsageSummary(period: period, sessionCount: 0, models: [], daily: [])
    }

    /// Build a summary from already-parsed sessions.
    ///
    /// A session is attributed to the period by its last activity (an
    /// approximation: a session straddling the boundary is counted whole).
    /// The per-day chart slices come from the sessions that count.
    static func make(period: StatsPeriod, sessions: [Session], pricing: ModelPricing, now: Date = .now) -> UsageSummary {
        let inPeriod = sessions.filter { session in
            let when = session.stats?.lastActivity ?? session.lastModified
            return period.contains(when, now: now)
        }
        let allModels = inPeriod.flatMap { $0.stats?.models ?? [] }.merged(pricing: pricing)
        let allDaily = inPeriod.flatMap { $0.stats?.daily ?? [] }
            .filter { period.contains($0.day, now: now) }
            .mergedByDay()
        return UsageSummary(period: period, sessionCount: inPeriod.count, models: allModels, daily: allDaily)
    }
}
