import Foundation
import Testing
@testable import ClaudeStats

@Suite("LeaderboardScoreBuilder")
struct LeaderboardScoreBuilderTests {
    private let builder = LeaderboardScoreBuilder()

    @Test("UTC period keys are stable")
    func periodKeys() {
        let now = dateUTC(2026, 5, 15, 13)

        #expect(LeaderboardPeriodCalculator.window(for: .day, now: now).periodKey == "2026-05-15")
        #expect(LeaderboardPeriodCalculator.window(for: .week, now: now).periodKey == "2026-W20")
        #expect(LeaderboardPeriodCalculator.window(for: .month, now: now).periodKey == "2026-05")
        #expect(LeaderboardPeriodCalculator.window(for: .allTime, now: now).periodKey == "all")
    }

    @Test("Token scores aggregate all providers and preserve cache semantics")
    func tokenScores() {
        let now = dateUTC(2026, 5, 15, 13)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let sessions = [
            session("claude", provider: .claude, at: dateUTC(2026, 5, 15, 10),
                    usage: TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadTokens: 1_000,
                                      cacheCreation5mTokens: 25, cacheCreation1hTokens: 0)),
            session("codex", provider: .codex, at: dateUTC(2026, 5, 15, 11),
                    usage: TokenUsage(inputTokens: 200, outputTokens: 75, cacheReadTokens: 2_000,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 5)),
            session("outside", provider: .claude, at: dateUTC(2026, 5, 14, 23),
                    usage: TokenUsage(inputTokens: 9_999, outputTokens: 0, cacheReadTokens: 0,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)),
        ]

        let submissions = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )

        #expect(submissions.first { $0.metric == .tokensWithCache }?.score == 3_455)
        #expect(submissions.first { $0.metric == .tokensWithoutCacheRead }?.score == 455)
        #expect(submissions.contains { $0.metric == .activityMinutes } == false)
    }

    @Test("Activity score is optional and measured in whole minutes")
    func activityScore() {
        let now = dateUTC(2026, 5, 15, 13)
        let window = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let sessions = [
            session("activity", provider: .claude, at: dateUTC(2026, 5, 15, 10),
                    usage: TokenUsage(inputTokens: 1, outputTokens: 0, cacheReadTokens: 0,
                                      cacheCreation5mTokens: 0, cacheCreation1hTokens: 0),
                    activityIntervals: [
                        DateInterval(start: dateUTC(2026, 5, 15, 9), end: dateUTC(2026, 5, 15, 9, minute: 40)),
                        DateInterval(start: dateUTC(2026, 5, 15, 9, minute: 30), end: dateUTC(2026, 5, 15, 10)),
                    ])
        ]

        let withoutActivity = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: false,
            window: window,
            now: now,
            appVersion: "test"
        )
        let withActivity = builder.submissions(
            sessions: sessions,
            nickname: "Ada",
            includeActivity: true,
            window: window,
            now: now,
            appVersion: "test"
        )

        #expect(withoutActivity.contains { $0.metric == .activityMinutes } == false)
        #expect(withActivity.first { $0.metric == .activityMinutes }?.score == 60)
    }

    private func session(_ id: String,
                         provider: ProviderKind,
                         at date: Date,
                         usage: TokenUsage,
                         activityIntervals: [DateInterval] = []) -> Session {
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: date,
            lastActivity: date,
            models: [ModelUsage(model: "model", messageCount: 1, usage: usage, pricing: TestPricing.table)],
            timeline: [],
            activityIntervals: activityIntervals
        )
        return Session(
            id: id,
            externalID: id,
            provider: provider,
            projectDirectoryName: "-project",
            filePath: "/tmp/\(id).jsonl",
            cwd: nil,
            lastModified: date,
            fileSize: 1,
            stats: stats
        )
    }

    private func dateUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
