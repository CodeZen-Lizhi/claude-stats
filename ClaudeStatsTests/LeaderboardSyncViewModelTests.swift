import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("LeaderboardSyncViewModel")
struct LeaderboardSyncViewModelTests {
    @Test("Disabled leaderboards do not submit")
    func disabledDoesNotSubmit() async {
        let fixture = makeFixture(enabled: false)

        await fixture.viewModel.syncNow()

        #expect(await fixture.client.submittedCount() == 0)
        #expect(fixture.viewModel.syncStatus == .disabled)
    }

    @Test("Missing iCloud account records a user-facing error")
    func missingAccountFails() async {
        let fixture = makeFixture(enabled: true)
        await fixture.client.setAccountState(.noAccount)

        await fixture.viewModel.syncNow()

        #expect(await fixture.client.submittedCount() == 0)
        #expect(fixture.preferences.leaderboardLastSyncError == "Sign in to iCloud")
        if case .failed(let reason) = fixture.viewModel.syncStatus {
            #expect(reason == "Sign in to iCloud")
        } else {
            Issue.record("Expected failed status")
        }
    }

    @Test("Daily sync is throttled unless forced")
    func throttling() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardLastSyncedAt = Date()

        await fixture.viewModel.syncIfDue(force: false)
        #expect(await fixture.client.submittedCount() == 0)

        await fixture.viewModel.syncIfDue(force: true)
        #expect(await fixture.client.submittedCount() == 8)
        #expect(fixture.preferences.leaderboardLastSubmittedPeriodKeys.contains("allTime:all"))
    }

    @Test("Daily scores fall back to the most recent UTC day with results")
    func dailyScoresFallbackToRecentDay() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        let previousDayKey = LeaderboardPeriodCalculator.window(
            for: .day,
            now: now.addingTimeInterval(-86_400)
        ).periodKey
        await fixture.client.setScores([
            previousDayKey: [
                LeaderboardScore(
                    id: "score",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: previousDayKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    updatedAt: now
                ),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .day, now: now)

        #expect(fixture.viewModel.lastLoadedPeriodKey == previousDayKey)
        #expect(fixture.viewModel.scores.count == 1)
        #expect(fixture.viewModel.scoreEmptyMessage == nil)
        #expect(await fixture.client.fetchedPeriodKeys() == ["2026-05-16", "2026-05-15"])
    }

    @Test("Daily scores show a recent-days empty message when no fallback exists")
    func dailyScoresEmptyMessage() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .day, now: dateUTC(2026, 5, 16, 8))

        #expect(fixture.viewModel.lastLoadedPeriodKey == "2026-05-16")
        #expect(fixture.viewModel.scores.isEmpty)
        #expect(fixture.viewModel.scoreEmptyMessage == "No daily scores in the last 7 UTC days yet.")
        #expect(await fixture.client.fetchedPeriodKeys().count == 7)
    }

    private func makeFixture(enabled: Bool) -> Fixture {
        let suiteName = "com.claudestats.tests.leaderboards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = Preferences(defaults: defaults)
        preferences.leaderboardsEnabled = enabled
        preferences.leaderboardNickname = "Ada"

        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        let now = Date()
        store.loadPreviewSessions([
            session("a", provider: .claude, at: now, tokens: 100),
            session("b", provider: .codex, at: now.addingTimeInterval(60), tokens: 200),
        ])
        let client = FakeLeaderboardClient()
        let viewModel = LeaderboardSyncViewModel(
            preferences: preferences,
            store: store,
            client: client,
            refreshBeforeSync: false
        )
        return Fixture(preferences: preferences, viewModel: viewModel, client: client)
    }

    private func session(_ id: String, provider: ProviderKind, at date: Date, tokens: Int) -> Session {
        let usage = TokenUsage(inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: date,
            lastActivity: date,
            models: [ModelUsage(model: "model", messageCount: 1, usage: usage, pricing: TestPricing.table)],
            timeline: []
        )
        return Session(id: id, externalID: id, provider: provider, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: date, fileSize: 1, stats: stats)
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

    private struct Fixture {
        let preferences: Preferences
        let viewModel: LeaderboardSyncViewModel
        let client: FakeLeaderboardClient
    }
}

private actor FakeLeaderboardClient: LeaderboardCloudServicing {
    private var state: LeaderboardCloudAccountState = .available
    private var submitted: [LeaderboardSubmission] = []
    private var scoresByPeriodKey: [String: [LeaderboardScore]] = [:]
    private var fetchedKeys: [String] = []

    func setAccountState(_ state: LeaderboardCloudAccountState) {
        self.state = state
    }

    func submittedCount() -> Int {
        submitted.count
    }

    func setScores(_ scoresByPeriodKey: [String: [LeaderboardScore]]) {
        self.scoresByPeriodKey = scoresByPeriodKey
    }

    func fetchedPeriodKeys() -> [String] {
        fetchedKeys
    }

    func accountState() async -> LeaderboardCloudAccountState {
        state
    }

    func submit(_ submissions: [LeaderboardSubmission]) async throws {
        submitted.append(contentsOf: submissions)
    }

    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int) async throws -> [LeaderboardScore] {
        fetchedKeys.append(periodKey)
        return scoresByPeriodKey[periodKey] ?? []
    }
}
