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
                    userHash: "userhash",
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: previousDayKey,
                    score: 42,
                    rank: 1,
                    nickname: "Ada",
                    avatarSeed: "avatar-ada",
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

    @Test("Enabled leaderboards generate a local avatar seed and bind the iCloud user hash")
    func enabledGeneratesAvatarSeedAndBindsUserHash() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.checkAccountStatus()

        #expect(fixture.preferences.leaderboardAvatarSeed.isEmpty == false)
        #expect(fixture.preferences.leaderboardProfileUserHash == "userhash")
        #expect(fixture.viewModel.currentUserHash == "userhash")
    }

    @Test("Randomizing avatar updates local seed and immediately saves the profile when available")
    func randomizeAvatarSavesProfile() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 1)
        #expect(await fixture.client.lastSavedProfile()?.avatarSeed == fixture.preferences.leaderboardAvatarSeed)
        #expect(fixture.preferences.leaderboardProfileUserHash == "userhash")
    }

    @Test("Randomizing avatar with unavailable iCloud keeps the local seed for a later sync")
    func randomizeAvatarUnavailableICloudStaysLocal() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"
        await fixture.client.setAccountState(.noAccount)

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 0)
        #expect(fixture.preferences.leaderboardLastSyncError == "Sign in to iCloud")
    }

    @Test("Randomizing avatar without a nickname stays local and asks for a nickname")
    func randomizeAvatarWithoutNicknameStaysLocal() async {
        let fixture = makeFixture(enabled: true)
        fixture.preferences.leaderboardNickname = ""
        fixture.preferences.leaderboardAvatarSeed = "avatar-old"

        await fixture.viewModel.randomizeAvatar()

        #expect(fixture.preferences.leaderboardAvatarSeed != "avatar-old")
        #expect(await fixture.client.savedProfileCount() == 0)
        #expect(fixture.viewModel.syncStatus == .needsNickname)
    }

    @Test("Current user score is matched by iCloud user hash instead of nickname")
    func currentUserScoreUsesUserHash() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.viewModel.checkAccountStatus()
        await fixture.client.setScores([
            "all": [
                score(id: "score-a", userHash: "otherhash", rank: 1, nickname: "Ada", value: 200, now: now),
                score(id: "score-b", userHash: "userhash", rank: 2, nickname: "Not Ada", value: 150, now: now),
            ],
        ])

        await fixture.viewModel.loadScores(metric: .tokensWithCache, period: .allTime, now: now)

        #expect(fixture.viewModel.currentUserScore?.rank == 2)
        #expect(fixture.viewModel.currentUserScore?.nickname == "Not Ada")
    }

    @Test("Daily score history fetches 14 windows oldest to current")
    func dailyScoreHistoryWindowOrder() async {
        let fixture = makeFixture(enabled: true)
        let anchor = LeaderboardPeriodCalculator.window(for: .day, now: dateUTC(2026, 5, 16, 8))

        await fixture.viewModel.loadScoreHistory(
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .day,
            anchorWindow: anchor
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys() == [
            "2026-05-03",
            "2026-05-04",
            "2026-05-05",
            "2026-05-06",
            "2026-05-07",
            "2026-05-08",
            "2026-05-09",
            "2026-05-10",
            "2026-05-11",
            "2026-05-12",
            "2026-05-13",
            "2026-05-14",
            "2026-05-15",
            "2026-05-16",
        ])
        #expect(fixture.viewModel.selectedUserHistory.count == 14)
    }

    @Test("Score history fills missing records with zero")
    func scoreHistoryFillsMissingRecordsWithZero() async {
        let fixture = makeFixture(enabled: true)
        let now = dateUTC(2026, 5, 16, 8)
        await fixture.client.setScores([
            "2026-05-15": [
                score(
                    id: "score-history",
                    userHash: "userhash",
                    rank: 1,
                    nickname: "Ada",
                    value: 42_000,
                    metric: .tokensWithCache,
                    period: .day,
                    periodKey: "2026-05-15",
                    now: now
                ),
            ],
        ])

        await fixture.viewModel.loadScoreHistory(
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .day,
            anchorWindow: LeaderboardPeriodCalculator.window(for: .day, now: now)
        )

        let valuesByKey = Dictionary(uniqueKeysWithValues: fixture.viewModel.selectedUserHistory.map { ($0.periodKey, $0.score) })
        #expect(valuesByKey["2026-05-14"] == 0)
        #expect(valuesByKey["2026-05-15"] == 42_000)
        #expect(valuesByKey["2026-05-16"] == 0)
    }

    @Test("All-time score history does not query CloudKit")
    func allTimeScoreHistoryDoesNotFetch() async {
        let fixture = makeFixture(enabled: true)

        await fixture.viewModel.loadScoreHistory(
            userHash: "userhash",
            metric: .tokensWithCache,
            period: .allTime,
            anchorWindow: LeaderboardPeriodCalculator.window(for: .allTime)
        )

        #expect(await fixture.client.fetchedHistoryPeriodKeys().isEmpty)
        #expect(fixture.viewModel.selectedUserHistory.isEmpty)
    }

    @Test("Selection resolver keeps preferred user before falling back")
    func selectionResolverKeepsPreferredUserBeforeFallback() {
        let now = dateUTC(2026, 5, 16, 8)
        let scores = [
            score(id: "score-a", userHash: "otherhash", rank: 1, nickname: "Ada", value: 200, now: now),
            score(id: "score-b", userHash: "userhash", rank: 2, nickname: "Not Ada", value: 150, now: now),
        ]

        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "otherhash",
            currentUserHash: "userhash",
            scores: scores
        )?.userHash == "otherhash")
        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "missing",
            currentUserHash: "userhash",
            scores: scores
        )?.userHash == "userhash")
        #expect(LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: "missing",
            currentUserHash: "also-missing",
            scores: scores
        )?.userHash == "otherhash")
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

    private func score(id: String,
                       userHash: String,
                       rank: Int,
                       nickname: String,
                       value: Int64,
                       metric: LeaderboardMetric = .tokensWithCache,
                       period: LeaderboardPeriod = .allTime,
                       periodKey: String = "all",
                       now: Date) -> LeaderboardScore {
        LeaderboardScore(
            id: id,
            userHash: userHash,
            metric: metric,
            period: period,
            periodKey: periodKey,
            score: value,
            rank: rank,
            nickname: nickname,
            avatarSeed: "avatar-\(id)",
            updatedAt: now
        )
    }

    private struct Fixture {
        let preferences: Preferences
        let viewModel: LeaderboardSyncViewModel
        let client: FakeLeaderboardClient
    }
}

private actor FakeLeaderboardClient: LeaderboardCloudServicing {
    private var state: LeaderboardCloudAccountState = .available
    private var userHash = "userhash"
    private var submitted: [LeaderboardSubmission] = []
    private var savedProfiles: [LeaderboardProfile] = []
    private var profilesByHash: [String: LeaderboardProfile] = [:]
    private var scoresByPeriodKey: [String: [LeaderboardScore]] = [:]
    private var fetchedKeys: [String] = []
    private var fetchedHistoryKeys: [String] = []

    func setAccountState(_ state: LeaderboardCloudAccountState) {
        self.state = state
    }

    func submittedCount() -> Int {
        submitted.count
    }

    func savedProfileCount() -> Int {
        savedProfiles.count
    }

    func lastSavedProfile() -> LeaderboardProfile? {
        savedProfiles.last
    }

    func setScores(_ scoresByPeriodKey: [String: [LeaderboardScore]]) {
        self.scoresByPeriodKey = scoresByPeriodKey
    }

    func fetchedPeriodKeys() -> [String] {
        fetchedKeys
    }

    func fetchedHistoryPeriodKeys() -> [String] {
        fetchedHistoryKeys
    }

    func accountState() async -> LeaderboardCloudAccountState {
        state
    }

    func currentUserHash() async throws -> String {
        switch state {
        case .available:
            return userHash
        case .noAccount:
            throw LeaderboardCloudError.noAccount
        case .restricted:
            throw LeaderboardCloudError.restricted
        case .unknown, .unavailable:
            throw LeaderboardCloudError.cloudKit(state.displayText)
        }
    }

    func saveProfile(_ profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        let saved = LeaderboardProfile(
            userHash: try await currentUserHash(),
            nickname: profile.nickname,
            avatarSeed: profile.avatarSeed,
            updatedAt: profile.updatedAt
        )
        savedProfiles.append(saved)
        profilesByHash[saved.userHash] = saved
        return saved
    }

    func fetchProfile(userHash: String) async throws -> LeaderboardProfile? {
        profilesByHash[userHash]
    }

    func submit(_ submissions: [LeaderboardSubmission], profile: LeaderboardProfileDraft) async throws -> LeaderboardProfile {
        submitted.append(contentsOf: submissions)
        return try await saveProfile(profile)
    }

    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int) async throws -> [LeaderboardScore] {
        fetchedKeys.append(periodKey)
        return scoresByPeriodKey[periodKey] ?? []
    }

    func fetchScoreHistory(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           windows: [LeaderboardPeriodWindow]) async throws -> [LeaderboardScoreHistoryPoint] {
        fetchedHistoryKeys.append(contentsOf: windows.map(\.periodKey))
        return windows.map { window in
            let score = scoresByPeriodKey[window.periodKey]?.first {
                $0.userHash == userHash && $0.metric == metric && $0.period == period
            }
            return LeaderboardScoreHistoryPoint(
                metric: metric,
                period: period,
                window: window,
                score: score?.score ?? 0,
                updatedAt: score?.updatedAt
            )
        }
    }
}
