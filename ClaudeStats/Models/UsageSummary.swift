import Foundation

/// Aggregate usage across many sessions, scoped to a ``StatsPeriod``.
struct UsageSummary: Sendable, Hashable {
    let period: StatsPeriod
    let sessionCount: Int
    let models: [ModelUsage]
    let messageCount: Int
    /// Hourly per-model buckets for the sessions counted in this period.
    let timeline: [ModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { totalCost(for: .standardAPI) }

    func totalTokens(includingCacheRead: Bool) -> Int {
        totalUsage.total(includingCacheRead: includingCacheRead)
    }

    func totalCost(for mode: CostEstimationMode) -> Double {
        models.reduce(0) { $0 + $1.estimatedCost(for: mode) }
    }

    static func empty(period: StatsPeriod) -> UsageSummary {
        UsageSummary(period: period, sessionCount: 0, models: [], messageCount: 0, timeline: [])
    }

    /// Build a summary from already-parsed sessions.
    ///
    /// A session is attributed to the period by its last activity (an
    /// approximation: a session straddling the boundary is counted whole).
    /// The timeline buckets come from the sessions that count, clipped to the
    /// period's lower bound.
    static func make(
        period: StatsPeriod,
        sessions: [Session],
        pricing: ModelPricing,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageSummary {
        let inPeriod = sessions.filter { session in
            let when = session.stats?.lastActivity ?? session.lastModified
            return period.contains(when, now: now, calendar: calendar)
        }
        let allModels = inPeriod.flatMap { $0.stats?.models ?? [] }.merged(pricing: pricing)
        let messageCount = inPeriod.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
        let allTimeline = timelineBuckets(for: inPeriod, calendar: calendar)
            .filter { period.contains($0.start, now: now, calendar: calendar) }
            .mergedByModelBucket()
        return UsageSummary(period: period, sessionCount: inPeriod.count, models: allModels, messageCount: messageCount, timeline: allTimeline)
    }

    /// Build a summary scoped to an explicit `[start, end]` range of calendar
    /// days (inclusive on both ends). The stored `period` is set to
    /// ``StatsPeriod/allTime`` purely so ``trendSeries(now:calendar:)`` picks
    /// daily granularity — the human-facing range label always comes from the
    /// originating ``PeriodSelection``, never from `period`.
    static func makeCustom(start: Date, end: Date, sessions: [Session], pricing: ModelPricing, calendar: Calendar = .current) -> UsageSummary {
        let lo = calendar.startOfDay(for: min(start, end))
        guard let hiExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end))) else {
            return .empty(period: .allTime)
        }
        let inRange = sessions.filter { session in
            let when = session.stats?.lastActivity ?? session.lastModified
            return when >= lo && when < hiExclusive
        }
        let allModels = inRange.flatMap { $0.stats?.models ?? [] }.merged(pricing: pricing)
        let messageCount = inRange.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
        let allTimeline = timelineBuckets(for: inRange, calendar: calendar)
            .filter { $0.start >= lo && $0.start < hiExclusive }
            .mergedByModelBucket()
        return UsageSummary(period: .allTime, sessionCount: inRange.count, models: allModels, messageCount: messageCount, timeline: allTimeline)
    }

    private static func timelineBuckets(for sessions: [Session], calendar: Calendar) -> [ModelBucket] {
        sessions.flatMap { timelineBuckets(for: $0, calendar: calendar) }
    }

    private static func timelineBuckets(for session: Session, calendar: Calendar) -> [ModelBucket] {
        guard let stats = session.stats else { return [] }
        guard stats.timeline.isEmpty else { return stats.timeline }

        let activityDate = stats.lastActivity ?? session.lastModified
        let bucketStart = calendar.dateInterval(of: .hour, for: activityDate)?.start ?? activityDate
        return stats.models.compactMap { model in
            guard model.usage.total > 0 else { return nil }
            return ModelBucket(model: model.model, start: bucketStart, usage: model.usage)
        }
    }

    /// Per-model series for the trend chart: hourly across *today* for
    /// ``StatsPeriod/today``, daily across the span of ``timeline`` otherwise.
    /// Every `(model × bucket-in-span)` is present (zero-filled) so each model
    /// has a continuous series to smooth.
    func trendSeries(now: Date = .now, calendar: Calendar = .current) -> TrendSeries {
        let models = timeline.modelsByTotalDescending
        guard !models.isEmpty else { return TrendSeries(granularity: period == .today ? .hour : .day, models: [], buckets: []) }

        let granularity: TrendGranularity = period == .today ? .hour : .day
        let unit: Calendar.Component = granularity == .hour ? .hour : .day

        let bucketed = timeline.rebucketed(by: unit, calendar: calendar)
        var byKey: [String: TokenUsage] = [:]   // "model|epoch" -> usage
        for b in bucketed { byKey["\(b.model)|\(b.start.timeIntervalSinceReferenceDate)"] = b.usage }

        // Domain of bucket starts.
        let starts: [Date]
        switch granularity {
        case .hour:
            let dayStart = calendar.startOfDay(for: now)
            starts = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
        case .day:
            guard let lo = bucketed.map(\.start).min(), let hi = bucketed.map(\.start).max() else {
                return TrendSeries(granularity: granularity, models: models, buckets: [])
            }
            var ds: [Date] = []
            var cur = lo
            while cur <= hi {
                ds.append(cur)
                guard let next = calendar.date(byAdding: unit, value: 1, to: cur) else { break }
                cur = next
            }
            starts = ds
        }

        var filled: [ModelBucket] = []
        filled.reserveCapacity(models.count * starts.count)
        for model in models {
            for start in starts {
                let usage = byKey["\(model)|\(start.timeIntervalSinceReferenceDate)"] ?? .zero
                filled.append(ModelBucket(model: model, start: start, usage: usage))
            }
        }
        return TrendSeries(granularity: granularity, models: models, buckets: filled)
    }
}

/// Time grain used by the Usage trend chart.
enum TrendGranularity: Sendable, Hashable { case hour, day }

/// The trend chart's data: a continuous, zero-filled per-model series.
struct TrendSeries: Sendable, Hashable {
    let granularity: TrendGranularity
    /// Models present, ordered by total tokens descending.
    let models: [String]
    /// Zero-filled buckets covering every `(model × bucket-in-span)`.
    let buckets: [ModelBucket]

    var isEmpty: Bool { buckets.allSatisfy { $0.tokens == 0 } }

    func buckets(for model: String) -> [ModelBucket] {
        buckets.filter { $0.model == model }.sorted { $0.start < $1.start }
    }
}
