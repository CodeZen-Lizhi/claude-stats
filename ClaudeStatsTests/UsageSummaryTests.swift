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
}
