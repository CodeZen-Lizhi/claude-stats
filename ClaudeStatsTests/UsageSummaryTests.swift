import Testing
import Foundation
@testable import ClaudeStats

@Suite("UsageSummary.makeCustom")
struct UsageSummaryTests {

    private let cal = Calendar.current

    private func tokens(_ n: Int) -> TokenUsage {
        TokenUsage(inputTokens: n, outputTokens: 0, cacheReadTokens: 0,
                   cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
    }

    /// A session whose activity and single timeline bucket both land on
    /// `dayStart + hour`.
    private func session(_ id: String, daysAgo n: Int, hour: Int, model: String, count: Int) -> Session {
        let dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -n, to: .now)!)
        let when = cal.date(byAdding: .hour, value: hour, to: dayStart)!
        let stats = SessionStats(
            title: id, messageCount: 1, firstActivity: when, lastActivity: when,
            models: [ModelUsage(model: model, messageCount: 1, usage: tokens(count), pricing: TestPricing.table)],
            timeline: [ModelBucket(model: model, start: when, usage: tokens(count))]
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func session(_ id: String, messageCount: Int, models: [ModelUsage]) -> Session {
        let when = Date.now
        let stats = SessionStats(
            title: id,
            messageCount: messageCount,
            firstActivity: when,
            lastActivity: when,
            models: models,
            timeline: []
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func legacySession(
        _ id: String,
        daysAgo n: Int,
        hour: Int,
        models: [ModelUsage],
        timeline: [ModelBucket] = []
    ) -> Session {
        let dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -n, to: .now)!)
        let when = cal.date(byAdding: .hour, value: hour, to: dayStart)!
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: when,
            lastActivity: when,
            models: models,
            timeline: timeline
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func model(_ name: String, count: Int) -> ModelUsage {
        ModelUsage(model: name, messageCount: 1, usage: tokens(count), pricing: TestPricing.table)
    }

    @Test("Only sessions inside the [start, end] day range count")
    func filtersByRange() {
        let sessions = [
            session("today", daysAgo: 0, hour: 10, model: "model-a", count: 100),
            session("d2", daysAgo: 2, hour: 10, model: "model-a", count: 200),
            session("d5", daysAgo: 5, hour: 10, model: "model-a", count: 400),
            session("d9", daysAgo: 9, hour: 10, model: "model-a", count: 800),
        ]
        let start = cal.date(byAdding: .day, value: -5, to: .now)!
        let end = cal.date(byAdding: .day, value: -1, to: .now)!   // excludes "today" and "d9"
        let summary = UsageSummary.makeCustom(start: start, end: end, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 2)            // d2 + d5
        #expect(summary.totalTokens == 600)
        #expect(summary.timeline.count == 2)
    }

    @Test("End day is inclusive")
    func endDayInclusive() {
        let sessions = [session("d3", daysAgo: 3, hour: 23, model: "model-a", count: 50)]
        let day = cal.date(byAdding: .day, value: -3, to: .now)!
        let summary = UsageSummary.makeCustom(start: day, end: day, sessions: sessions, pricing: TestPricing.table)
        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 50)
    }

    @Test("Custom-range summaries chart at daily granularity")
    func dailyGranularity() {
        let sessions = [
            session("d1", daysAgo: 1, hour: 9, model: "model-a", count: 10),
            session("d3", daysAgo: 3, hour: 9, model: "model-a", count: 20),
        ]
        let start = cal.date(byAdding: .day, value: -4, to: .now)!
        let summary = UsageSummary.makeCustom(start: start, end: .now, sessions: sessions, pricing: TestPricing.table)
        #expect(summary.trendSeries().granularity == .day)
    }

    @Test("Message counts come from session stats instead of model rows")
    func messageCountUsesSessionStats() {
        let visibleModel = ModelUsage(model: "model-a", messageCount: 1, usage: tokens(10), pricing: TestPricing.table)
        let summary = UsageSummary.make(period: .allTime, sessions: [
            session("synthetic-filtered", messageCount: 3, models: [visibleModel]),
        ], pricing: TestPricing.table)

        #expect(summary.messageCount == 3)
        #expect(summary.models.first?.messageCount == 1)
    }

    @Test("Total cost can be read by selected estimate mode")
    func totalCostByMode() {
        let model = ModelUsage(
            model: "model-a",
            messageCount: 1,
            usage: tokens(10),
            costEstimate: CostEstimate(standardAPI: 1.25, detailedBilling: 3.5)
        )
        let summary = UsageSummary.make(period: .allTime, sessions: [
            session("cost-mode", messageCount: 1, models: [model]),
        ], pricing: TestPricing.table)

        #expect(summary.totalCost(for: .standardAPI) == 1.25)
        #expect(summary.totalCost(for: .detailedBilling) == 3.5)
    }

    @Test("Legacy sessions without timeline generate fallback trend buckets")
    func legacySessionsWithoutTimelineGenerateFallbackBuckets() {
        let sessions = [
            legacySession("legacy", daysAgo: 1, hour: 13, models: [
                model("model-a", count: 100),
                model("model-b", count: 250),
            ]),
        ]

        let summary = UsageSummary.make(period: .allTime, sessions: sessions, pricing: TestPricing.table)
        let expectedStart = cal.dateInterval(of: .hour, for: sessions[0].lastModified)!.start
        let series = summary.trendSeries()

        #expect(summary.timeline.count == 2)
        #expect(Set(summary.timeline.map(\.start)) == [expectedStart])
        #expect(summary.timeline.totalTokens == 350)
        #expect(series.models == ["model-b", "model-a"])
        #expect(series.isEmpty == false)
    }

    @Test("Fallback buckets follow selected period filters")
    func fallbackBucketsFollowSelectedPeriodFilters() {
        let sessions = [
            legacySession("today", daysAgo: 0, hour: 1, models: [model("model-a", count: 120)]),
            legacySession("old", daysAgo: 2, hour: 1, models: [model("model-a", count: 900)]),
        ]

        let summary = UsageSummary.make(period: .today, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 120)
        #expect(summary.timeline.totalTokens == 120)
        #expect(summary.trendSeries().isEmpty == false)
    }

    @Test("Fallback buckets follow custom range filters")
    func fallbackBucketsFollowCustomRangeFilters() {
        let sessions = [
            legacySession("inside", daysAgo: 3, hour: 1, models: [model("model-a", count: 120)]),
            legacySession("outside", daysAgo: 9, hour: 1, models: [model("model-a", count: 900)]),
        ]
        let start = cal.date(byAdding: .day, value: -4, to: .now)!
        let end = cal.date(byAdding: .day, value: -2, to: .now)!

        let summary = UsageSummary.makeCustom(start: start, end: end, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 120)
        #expect(summary.timeline.totalTokens == 120)
        #expect(summary.trendSeries().isEmpty == false)
    }

    @Test("Existing timeline is not double counted by model fallback")
    func existingTimelineIsNotDoubleCounted() {
        let bucketStart = cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: .now))!
        let sessions = [
            legacySession(
                "timeline",
                daysAgo: 0,
                hour: 10,
                models: [model("model-a", count: 999)],
                timeline: [ModelBucket(model: "model-a", start: bucketStart, usage: tokens(100))]
            ),
        ]

        let summary = UsageSummary.make(period: .allTime, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.totalTokens == 999)
        #expect(summary.timeline.count == 1)
        #expect(summary.timeline.totalTokens == 100)
    }

    @MainActor
    @Test("Usage derived data is keyed by data inputs, not layout")
    func usageDerivedDataKeyedByDataInputs() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            session("derived", daysAgo: 0, hour: 10, model: "model-a", count: 120),
        ])

        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )
        let snapshot = UsageDerivedData.make(key: key, store: store)

        #expect(snapshot.summary.totalTokens == 120)
        #expect(snapshot.series.models == ["model-a"])
        #expect(key == UsageDerivedData.Key(period: .allTime, provider: .claude, lastRefreshedAt: store.lastRefreshedAt))
        #expect(key != UsageDerivedData.Key(period: .last7Days, provider: .claude, lastRefreshedAt: store.lastRefreshedAt))
        #expect(key != UsageDerivedData.Key(period: .allTime, provider: .codex, lastRefreshedAt: store.lastRefreshedAt))
    }

    @MainActor
    @Test("Usage derived data and model breakdown handle legacy sessions without timeline")
    func usageDerivedDataHandlesLegacySessionsWithoutTimeline() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            legacySession("legacy-derived", daysAgo: 0, hour: 10, models: [model("model-a", count: 120)]),
        ])
        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )

        let data = UsageDerivedData.make(key: key, store: store)
        let breakdown = UsageModelBreakdownSnapshot(
            key: UsageModelBreakdownSnapshot.Key(
                seriesID: data.key.chartSeriesID,
                includeCacheInTokens: true,
                costEstimationMode: .standardAPI
            ),
            models: data.summary.models,
            series: data.series,
            displayName: { $0 }
        )

        #expect(data.summary.totalTokens == 120)
        #expect(data.series.models == ["model-a"])
        #expect(data.series.isEmpty == false)
        #expect(breakdown.rows.map(\.id) == ["model-a"])
    }
}
