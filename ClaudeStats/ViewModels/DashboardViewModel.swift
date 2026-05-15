import Foundation
import Observation

/// Per-period summary of the user's Claude activity. All numbers are derived
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
    /// Canonical model id with the most tokens spent across `period`.
    var favoriteModel: String?

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

/// Drives the Dashboard page: 8 stat cards keyed by `period`, a fixed
/// 3-month heatmap, and a model breakdown for the Models tab. GitHub state
/// lives in `GitHubViewModel` and is rendered from the Git page.
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
    private(set) var modelBreakdown: [ModelUsage] = []
    /// Per-model daily series for the Models tab's stacked bar chart. Daily
    /// granularity for every dashboard period (we never select `.today` here).
    private(set) var modelTrend: TrendSeries = TrendSeries(granularity: .day, models: [], buckets: [])
    private(set) var isLoading = false
    private(set) var reloadToken: UInt64 = 0

    private let calendar = Calendar.current
    private let pricing: ModelPricing

    /// Number of trailing days the heatmap spans (rolling, ends today).
    static let heatmapDayCount = 90

    init(pricing: ModelPricing = .fallback) {
        self.pricing = pricing
    }

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
        let pricing = pricing
        let period = period
        let now = Date.now
        let heatmapInterval = heatmapInterval(now: now)

        let result = await Task.detached(priority: .userInitiated) { () -> ReloadResult in
            // 1. Stats for the selected period — reuses the existing aggregator.
            let summary = UsageSummary.make(period: period, sessions: sessions, pricing: pricing, now: now)
            let activeDays = Self.activeDayCount(sessions: sessions, period: period, calendar: cal, now: now)
            let (current, longest) = Self.streaks(sessions: sessions, calendar: cal, now: now)
            let peakHour = Self.peakHour(timeline: summary.timeline, calendar: cal)

            // 2. Heatmap: tokens per day across the 3-month window.
            let heatmap = Self.heatmapCells(sessions: sessions, range: heatmapInterval, calendar: cal)
            let heatmapActive = heatmap.reduce(0) { $0 + ($1.value > 0 ? 1 : 0) }

            // 3. Models tab: top models in the period (sorted desc) plus a
            //    zero-filled daily per-model series for the stacked chart.
            let models = summary.models
            let trend = summary.trendSeries(now: now, calendar: cal)

            return ReloadResult(
                stats: DashboardStats(
                    sessions: summary.sessionCount,
                    messages: summary.messageCount,
                    totalTokens: summary.totalTokens,
                    totalCost: summary.totalCost,
                    activeDays: activeDays,
                    currentStreak: current,
                    longestStreak: longest,
                    peakHour: peakHour,
                    favoriteModel: models.first?.model
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
        let modelBreakdown: [ModelUsage]
        let modelTrend: TrendSeries
    }

    // MARK: - Pure aggregations (nonisolated, called from Task.detached)

    /// Days in `period` that contain at least one session's last activity.
    nonisolated private static func activeDayCount(sessions: [Session], period: StatsPeriod, calendar cal: Calendar, now: Date) -> Int {
        var days: Set<Date> = []
        for session in sessions {
            let when = session.stats?.lastActivity ?? session.lastModified
            guard period.contains(when, now: now, calendar: cal) else { continue }
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

    /// Tokens-per-day cells across `range`. Mirrors the bucketing in
    /// `DashboardActivityBuilder.bucket(sessions:range:)` but inlined so we
    /// don't roundtrip through another detached task.
    nonisolated private static func heatmapCells(sessions: [Session], range: DateInterval, calendar cal: Calendar) -> [HeatmapCell] {
        var byDay: [Date: Int] = [:]
        for session in sessions {
            guard let timeline = session.stats?.timeline else { continue }
            for bucket in timeline.rebucketed(by: .day, calendar: cal) where range.contains(bucket.start) {
                byDay[bucket.start, default: 0] += bucket.tokens
            }
        }
        return byDay
            .map { HeatmapCell(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}
