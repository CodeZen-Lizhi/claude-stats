import Foundation
import Observation

/// Per-period summary of the user's AI coding activity. All numbers are derived
/// from already-parsed sessions; `reload(...)` populates this off-main so view
/// bodies only read precomputed values.
struct DashboardStats: Sendable, Hashable {
    var sessions: Int
    var messages: Int
    var totalTokens: Int
    var totalCost: Double
    var activeDays: Int
    /// Consecutive days, counting back from today (or yesterday if today is
    /// empty), where there was any session activity.
    var currentStreak: Int
    /// Longest run of consecutive active days across all of history.
    var longestStreak: Int
    /// Hour-of-day (0…23) with the most token spend; `nil` when there is no
    /// activity at all.
    var peakHour: Int?
    /// Provider-qualified model id with the most tokens spent across `period`.
    var favoriteModel: DashboardModelKey?

    static let empty = DashboardStats(
        sessions: 0,
        messages: 0,
        totalTokens: 0,
        totalCost: 0,
        activeDays: 0,
        currentStreak: 0,
        longestStreak: 0,
        peakHour: nil,
        favoriteModel: nil
    )
}

/// Dashboard-specific model identity. The Dashboard aggregates all providers,
/// so the provider must travel with the model id to avoid merging unrelated
/// models that happen to share the same raw string.
struct DashboardModelKey: Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let model: String

    var id: String { "\(provider.rawValue)|\(model)" }

    init(provider: ProviderKind, model: String) {
        self.provider = provider
        self.model = model
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let provider = ProviderKind(rawValue: String(parts[0])) else {
            return nil
        }
        self.provider = provider
        self.model = String(parts[1])
    }
}

struct DashboardModelUsage: Sendable, Hashable, Identifiable {
    let key: DashboardModelKey
    let messageCount: Int
    let usage: TokenUsage
    let costEstimate: CostEstimate

    var id: String { key.id }
    var estimatedCost: Double { costEstimate.standardAPI }

    func estimatedCost(for mode: CostEstimationMode) -> Double {
        costEstimate.value(for: mode)
    }
}

/// Drives the Dashboard page: 8 stat cards keyed by `period`, a fixed
/// 3-month all-provider heatmap, and an all-provider model breakdown for the
/// Models tab. GitHub state lives in `GitHubViewModel` and is rendered from the
/// Git page.
///
/// `reload(sessions:)` runs the full aggregation off-main in a single
/// `Task.detached`, so view bodies stay cheap and SwiftUI's update cycle
/// receives one batched assignment.
@MainActor
@Observable
final class DashboardViewModel {
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case overview, models
        var id: String { rawValue }
    }

    var section: Section = .overview
    var period: StatsPeriod = .last30Days {
        didSet { if period != oldValue { reloadToken &+= 1 } }
    }

    private(set) var stats: DashboardStats = .empty
    private(set) var heatmapCells: [HeatmapCell] = []
    /// Count of cells in the 3-month heatmap with positive activity. Mirrors
    /// `heatmapCells.filter { $0.value > 0 }.count` but computed off-main
    /// during `reload(sessions:)` so the view body doesn't walk the array.
    private(set) var heatmapActiveDays: Int = 0
    private(set) var modelBreakdown: [DashboardModelUsage] = []
    /// Per-model daily series for the Models tab's stacked bar chart. Daily
    /// granularity for every dashboard period (we never select `.today` here).
    private(set) var modelTrend: TrendSeries = TrendSeries(granularity: .day, models: [], buckets: [])
    private(set) var isLoading = false
    private(set) var reloadToken: UInt64 = 0

    private let calendar = Calendar.current

    /// Number of trailing days the heatmap spans (rolling, ends today).
    static let heatmapDayCount = 90

    init(pricing _: ModelPricing = .fallback) {}

    func bumpReload() { reloadToken &+= 1 }

    /// Rolling interval the heatmap covers: `[today − (heatmapDayCount − 1), today + 1d)`.
    func heatmapInterval(now: Date = .now) -> DateInterval {
        let cal = calendar
        let endExclusive = cal.dateInterval(of: .day, for: now)?.end ?? now
        let start = cal.date(byAdding: .day, value: -(Self.heatmapDayCount - 1), to: cal.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: endExclusive)
    }

    /// Recompute the overview off-main. Captures a local `Calendar` so the
    /// detached block stays Sendable under Swift 6 strict concurrency.
    func reload(sessions: [Session]) async {
        isLoading = true
        defer { isLoading = false }

        let cal = calendar
        let period = period
        let now = Date.now
        let heatmapInterval = heatmapInterval(now: now)

        let result = await Task.detached(priority: .userInitiated) { () -> ReloadResult in
            // 1. Stats for the selected period across every parsed provider.
            let inPeriod = Self.sessions(in: period, sessions: sessions, calendar: cal, now: now)
            let models = Self.modelBreakdown(for: inPeriod)
            let timeline = Self.timelineBuckets(for: inPeriod, period: period, calendar: cal, now: now)
            let totalUsage = models.reduce(.zero) { $0 + $1.usage }
            let totalCost = models.reduce(0) { $0 + $1.estimatedCost }
            let messageCount = inPeriod.reduce(0) { $0 + ($1.stats?.messageCount ?? 0) }
            let activeDays = Self.activeDayCount(sessions: inPeriod, calendar: cal)
            let (current, longest) = Self.streaks(sessions: sessions, calendar: cal, now: now)
            let peakHour = Self.peakHour(timeline: timeline, calendar: cal)

            // 2. Heatmap: all-provider tokens per day across the 3-month window.
            let heatmap = Self.heatmapCells(sessions: sessions, range: heatmapInterval, calendar: cal)
            let heatmapActive = heatmap.reduce(0) { $0 + ($1.value > 0 ? 1 : 0) }

            // 3. Models tab: provider-aware top models plus a zero-filled
            //    daily per-model series in matching order for the stacked chart.
            let trend = Self.trendSeries(
                timeline: timeline,
                models: models,
                period: period,
                now: now,
                calendar: cal
            )

            return ReloadResult(
                stats: DashboardStats(
                    sessions: inPeriod.count,
                    messages: messageCount,
                    totalTokens: totalUsage.total,
                    totalCost: totalCost,
                    activeDays: activeDays,
                    currentStreak: current,
                    longestStreak: longest,
                    peakHour: peakHour,
                    favoriteModel: models.first?.key
                ),
                heatmapCells: heatmap,
                heatmapActiveDays: heatmapActive,
                modelBreakdown: models,
                modelTrend: trend
            )
        }.value

        stats = result.stats
        heatmapCells = result.heatmapCells
        heatmapActiveDays = result.heatmapActiveDays
        modelBreakdown = result.modelBreakdown
        modelTrend = result.modelTrend
    }

    private struct ReloadResult: Sendable {
        let stats: DashboardStats
        let heatmapCells: [HeatmapCell]
        let heatmapActiveDays: Int
        let modelBreakdown: [DashboardModelUsage]
        let modelTrend: TrendSeries
    }

    // MARK: - Pure aggregations (nonisolated, called from Task.detached)

    nonisolated private static func sessions(in period: StatsPeriod, sessions: [Session], calendar cal: Calendar, now: Date) -> [Session] {
        sessions.filter { session in
            let when = session.stats?.lastActivity ?? session.lastModified
            return period.contains(when, now: now, calendar: cal)
        }
    }

    /// Days in the already-selected sessions that contain at least one
    /// session's last activity.
    nonisolated private static func activeDayCount(sessions: [Session], calendar cal: Calendar) -> Int {
        var days: Set<Date> = []
        for session in sessions {
            let when = session.stats?.lastActivity ?? session.lastModified
            days.insert(cal.startOfDay(for: when))
        }
        return days.count
    }

    /// `(currentStreak, longestStreak)` walking the set of days with any
    /// session activity across all history (streaks are a long-term motivation
    /// signal and don't depend on the selected range).
    nonisolated private static func streaks(sessions: [Session], calendar cal: Calendar, now: Date) -> (Int, Int) {
        var days: Set<Date> = []
        for session in sessions {
            let when = session.stats?.lastActivity ?? session.lastModified
            days.insert(cal.startOfDay(for: when))
        }
        guard !days.isEmpty else { return (0, 0) }

        // Longest streak: sort ascending, walk and accumulate.
        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if let prevPlusOne = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]), prevPlusOne == sorted[i] {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        // Current streak: count back from today; allow one-day grace if today
        // is empty (user hasn't started yet but was active yesterday).
        let today = cal.startOfDay(for: now)
        var current = 0
        var cursor = today
        if !days.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: today) ?? today
            if !days.contains(cursor) { return (0, longest) }
        }
        while days.contains(cursor) {
            current += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return (current, longest)
    }

    /// Hour 0…23 with the most token spend across `timeline`; `nil` if empty.
    nonisolated private static func peakHour(timeline: [ModelBucket], calendar cal: Calendar) -> Int? {
        guard !timeline.isEmpty else { return nil }
        var byHour: [Int: Int] = [:]
        for bucket in timeline {
            let hour = cal.component(.hour, from: bucket.start)
            byHour[hour, default: 0] += bucket.tokens
        }
        return byHour.max(by: { $0.value < $1.value })?.key
    }

    nonisolated private static func modelBreakdown(for sessions: [Session]) -> [DashboardModelUsage] {
        var byModel: [DashboardModelKey: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        for session in sessions {
            guard let stats = session.stats else { continue }
            for model in stats.models {
                let key = DashboardModelKey(provider: session.provider, model: model.model)
                var acc = byModel[key] ?? (0, .zero, .zero)
                acc.count += model.messageCount
                acc.usage += model.usage
                acc.cost += model.costEstimate
                byModel[key] = acc
            }
        }

        return byModel
            .map { key, value in
                DashboardModelUsage(
                    key: key,
                    messageCount: value.count,
                    usage: value.usage,
                    costEstimate: value.cost
                )
            }
            .sorted { lhs, rhs in
                lhs.usage.total != rhs.usage.total
                    ? lhs.usage.total > rhs.usage.total
                    : lhs.id < rhs.id
            }
    }

    nonisolated private static func timelineBuckets(
        for sessions: [Session],
        period: StatsPeriod,
        calendar cal: Calendar,
        now: Date
    ) -> [ModelBucket] {
        sessions
            .flatMap { timelineBuckets(for: $0, calendar: cal) }
            .filter { period.contains($0.start, now: now, calendar: cal) }
            .mergedByModelBucket()
    }

    nonisolated private static func timelineBuckets(for session: Session, calendar cal: Calendar) -> [ModelBucket] {
        guard let stats = session.stats else { return [] }
        let buckets: [ModelBucket]
        if stats.timeline.isEmpty {
            let activityDate = stats.lastActivity ?? session.lastModified
            let bucketStart = cal.dateInterval(of: .hour, for: activityDate)?.start ?? activityDate
            buckets = stats.models.compactMap { model in
                guard model.usage.total > 0 else { return nil }
                return ModelBucket(model: model.model, start: bucketStart, usage: model.usage)
            }
        } else {
            buckets = stats.timeline
        }

        return buckets.map { bucket in
            ModelBucket(
                model: DashboardModelKey(provider: session.provider, model: bucket.model).id,
                start: bucket.start,
                usage: bucket.usage
            )
        }
    }

    nonisolated private static func trendSeries(
        timeline: [ModelBucket],
        models: [DashboardModelUsage],
        period: StatsPeriod,
        now: Date,
        calendar cal: Calendar
    ) -> TrendSeries {
        let modelIDs = models.map(\.id)
        let granularity: TrendGranularity = period == .today ? .hour : .day
        guard !modelIDs.isEmpty else {
            return TrendSeries(granularity: granularity, models: [], buckets: [])
        }

        let unit: Calendar.Component = granularity == .hour ? .hour : .day
        let bucketed = timeline.rebucketed(by: unit, calendar: cal)
        var byKey: [String: TokenUsage] = [:]
        for bucket in bucketed {
            byKey["\(bucket.model)|\(bucket.start.timeIntervalSinceReferenceDate)"] = bucket.usage
        }

        let starts: [Date]
        switch granularity {
        case .hour:
            let dayStart = cal.startOfDay(for: now)
            starts = (0..<24).compactMap { cal.date(byAdding: .hour, value: $0, to: dayStart) }
        case .day:
            guard let lo = bucketed.map(\.start).min(), let hi = bucketed.map(\.start).max() else {
                return TrendSeries(granularity: granularity, models: modelIDs, buckets: [])
            }
            var ds: [Date] = []
            var cur = lo
            while cur <= hi {
                ds.append(cur)
                guard let next = cal.date(byAdding: unit, value: 1, to: cur) else { break }
                cur = next
            }
            starts = ds
        }

        var filled: [ModelBucket] = []
        filled.reserveCapacity(modelIDs.count * starts.count)
        for model in modelIDs {
            for start in starts {
                let usage = byKey["\(model)|\(start.timeIntervalSinceReferenceDate)"] ?? .zero
                filled.append(ModelBucket(model: model, start: start, usage: usage))
            }
        }
        return TrendSeries(granularity: granularity, models: modelIDs, buckets: filled)
    }

    /// Tokens-per-day cells across `range`. Mirrors the bucketing in
    /// `DashboardActivityBuilder.bucket(sessions:range:)` but inlined so we
    /// don't roundtrip through another detached task.
    nonisolated private static func heatmapCells(sessions: [Session], range: DateInterval, calendar cal: Calendar) -> [HeatmapCell] {
        var byDay: [Date: Int] = [:]
        for session in sessions {
            for bucket in timelineBuckets(for: session, calendar: cal).rebucketed(by: .day, calendar: cal) where range.contains(bucket.start) {
                byDay[bucket.start, default: 0] += bucket.tokens
            }
        }
        return byDay
            .map { HeatmapCell(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}
