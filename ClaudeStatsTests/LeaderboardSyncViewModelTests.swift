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

    private struct Fixture {
        let preferences: Preferences
        let viewModel: LeaderboardSyncViewModel
        let client: FakeLeaderboardClient
    }
}

private actor FakeLeaderboardClient: LeaderboardCloudServicing {
    private var state: LeaderboardCloudAccountState = .available
    private var submitted: [LeaderboardSubmission] = []

    func setAccountState(_ state: LeaderboardCloudAccountState) {
        self.state = state
    }

    func submittedCount() -> Int {
        submitted.count
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
        []
    }
}
