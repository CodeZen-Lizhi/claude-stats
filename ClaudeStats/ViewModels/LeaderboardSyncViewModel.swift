import Foundation
import Observation

@MainActor
@Observable
final class LeaderboardSyncViewModel {
    enum SyncStatus: Sendable, Equatable {
        case disabled
        case idle
        case needsNickname
        case checkingAccount
        case syncing
        case synced(Date)
        case failed(String)

        var displayText: String {
            switch self {
            case .disabled: "Disabled"
            case .idle: "Ready"
            case .needsNickname: "Choose a nickname"
            case .checkingAccount: "Checking iCloud…"
            case .syncing: "Syncing…"
            case .synced(let date): "Synced \(Format.relativeDate(date))"
            case .failed(let reason): reason
            }
        }
    }

    private(set) var syncStatus: SyncStatus = .disabled
    private(set) var accountState: LeaderboardCloudAccountState = .unknown
    private(set) var scores: [LeaderboardScore] = []
    private(set) var isLoadingScores = false
    private(set) var scoreError: String?
    private(set) var scoreEmptyMessage: String?
    private(set) var lastLoadedPeriodKey: String?
    private(set) var currentUserHash: String?
    private(set) var isSavingProfile = false

    var avatarSeed: String {
        preferences.leaderboardAvatarSeed.isEmpty
            ? LeaderboardAvatarSeed.fallback
            : preferences.leaderboardAvatarSeed
    }

    var currentUserScore: LeaderboardScore? {
        guard let currentUserHash else { return nil }
        return scores.first { $0.userHash == currentUserHash }
    }

    private let preferences: Preferences
    private let store: SessionStore
    private let client: any LeaderboardCloudServicing
    private let builder: LeaderboardScoreBuilder
    private let refreshBeforeSync: Bool
    private var syncTask: Task<Void, Never>?

    private static let syncInterval: TimeInterval = 24 * 60 * 60

    init(preferences: Preferences,
         store: SessionStore,
         client: any LeaderboardCloudServicing = CloudKitLeaderboardClient(),
         builder: LeaderboardScoreBuilder = LeaderboardScoreBuilder(),
         refreshBeforeSync: Bool = true) {
        self.preferences = preferences
        self.store = store
        self.client = client
        self.builder = builder
        self.refreshBeforeSync = refreshBeforeSync
        syncStatus = preferences.leaderboardsEnabled ? .idle : .disabled
    }

    func start() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.syncIfDue(force: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.syncInterval))
                guard !Task.isCancelled else { break }
                await self?.syncIfDue(force: false)
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
    }

    func checkAccountStatus() async {
        guard preferences.leaderboardsEnabled else {
            syncStatus = .disabled
            accountState = .unknown
            return
        }
        ensureLocalAvatarSeed()
        syncStatus = .checkingAccount
        accountState = await client.accountState()
        if accountState == .available {
            do {
                try await reconcileCurrentUserProfile()
            } catch {
                let reason = userFacingMessage(error)
                preferences.leaderboardLastSyncError = reason
                syncStatus = .failed(reason)
                return
            }
        }
        syncStatus = statusAfterAccountCheck()
    }

    func syncNow() async {
        await syncIfDue(force: true)
    }

    func syncIfDue(force: Bool) async {
        guard preferences.leaderboardsEnabled else {
            syncStatus = .disabled
            return
        }
        ensureLocalAvatarSeed()
        let nickname = preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            syncStatus = .needsNickname
            return
        }
        if !force, let last = preferences.leaderboardLastSyncedAt,
           Date().timeIntervalSince(last) < Self.syncInterval {
            await reconcileCurrentUserProfileIfPossible()
            syncStatus = .synced(last)
            return
        }

        syncStatus = .checkingAccount
        accountState = await client.accountState()
        guard accountState == .available else {
            let reason = accountState.displayText
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            return
        }
        do {
            try await reconcileCurrentUserProfile()
        } catch {
            let reason = userFacingMessage(error)
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            return
        }

        syncStatus = .syncing
        if refreshBeforeSync {
            await store.refresh()
        }
        let includeActivity = preferences.aiActivityAnalysisEnabled && ScreenTimeService.canRead()
        let submissions = builder.submissions(
            sessions: store.sessions,
            nickname: nickname,
            includeActivity: includeActivity,
            now: .now
        )
        guard !submissions.isEmpty else {
            let reason = "No leaderboard scores to submit yet."
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            return
        }

        do {
            let profile = try await client.submit(
                submissions,
                profile: LeaderboardProfileDraft(nickname: nickname, avatarSeed: ensureLocalAvatarSeed())
            )
            remember(profile: profile)
            let syncedAt = Date()
            preferences.leaderboardLastSyncedAt = syncedAt
            preferences.leaderboardLastSyncError = ""
            preferences.leaderboardLastSubmittedPeriodKeys = submissions
                .map { "\($0.period.rawValue):\($0.periodKey)" }
                .uniqued()
                .sorted()
            syncStatus = .synced(syncedAt)
        } catch let error as LeaderboardCloudError {
            preferences.leaderboardLastSyncError = error.description
            syncStatus = .failed(error.description)
            Log.network.error("Leaderboard sync failed: \(error.description, privacy: .public)")
        } catch {
            let reason = error.localizedDescription
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            Log.network.error("Leaderboard sync failed: \(reason, privacy: .public)")
        }
    }

    func loadScores(metric: LeaderboardMetric, period: LeaderboardPeriod, now: Date = .now) async {
        ensureLocalAvatarSeed()
        await reconcileCurrentUserProfileIfPossible()
        let requestedWindow = LeaderboardPeriodCalculator.window(for: period, now: now)
        lastLoadedPeriodKey = requestedWindow.periodKey
        scoreError = nil
        scoreEmptyMessage = nil
        isLoadingScores = true
        defer { isLoadingScores = false }

        do {
            for window in scoreLookupWindows(for: period, now: now) {
                let fetched = try await client.fetchScores(
                    metric: metric,
                    period: period,
                    periodKey: window.periodKey,
                    limit: 100
                )
                if !fetched.isEmpty {
                    scores = fetched
                    lastLoadedPeriodKey = window.periodKey
                    return
                }
            }
            scores = []
            lastLoadedPeriodKey = requestedWindow.periodKey
            scoreEmptyMessage = emptyScoresMessage(for: period)
        } catch let error as LeaderboardCloudError {
            scores = []
            scoreEmptyMessage = nil
            scoreError = error.description
        } catch {
            scores = []
            scoreEmptyMessage = nil
            scoreError = error.localizedDescription
        }
    }

    func randomizeAvatar() async {
        let previous = ensureLocalAvatarSeed()
        var next = LeaderboardAvatarSeed.random()
        while next == previous {
            next = LeaderboardAvatarSeed.random()
        }
        preferences.leaderboardAvatarSeed = next

        guard preferences.leaderboardsEnabled else {
            syncStatus = .disabled
            return
        }
        await saveCurrentProfileIfPossible()
    }

    private func scoreLookupWindows(for period: LeaderboardPeriod, now: Date) -> [LeaderboardPeriodWindow] {
        guard period == .day else {
            return [LeaderboardPeriodCalculator.window(for: period, now: now)]
        }
        return (0..<7).map { dayOffset in
            LeaderboardPeriodCalculator.window(
                for: .day,
                now: now.addingTimeInterval(TimeInterval(-dayOffset * 86_400))
            )
        }
    }

    private func emptyScoresMessage(for period: LeaderboardPeriod) -> String {
        switch period {
        case .day:
            return "No daily scores in the last 7 UTC days yet."
        case .week, .month, .allTime:
            return "No scores for this UTC period yet."
        }
    }

    @discardableResult
    private func ensureLocalAvatarSeed() -> String {
        let trimmed = preferences.leaderboardAvatarSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let seed = LeaderboardAvatarSeed.random()
            preferences.leaderboardAvatarSeed = seed
            return seed
        }
        return trimmed
    }

    private func reconcileCurrentUserProfileIfPossible() async {
        guard preferences.leaderboardsEnabled else { return }
        do {
            try await reconcileCurrentUserProfile()
        } catch {
            Log.network.debug("Leaderboard profile reconcile skipped: \(self.userFacingMessage(error), privacy: .public)")
        }
    }

    private func reconcileCurrentUserProfile() async throws {
        let userHash = try await client.currentUserHash()
        currentUserHash = userHash

        let storedUserHash = preferences.leaderboardProfileUserHash
        let needsRemoteProfile = storedUserHash != userHash
            || preferences.leaderboardAvatarSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsRemoteProfile else { return }

        preferences.leaderboardProfileUserHash = userHash
        if let profile = try await client.fetchProfile(userHash: userHash),
           let avatarSeed = profile.avatarSeed,
           !avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.leaderboardAvatarSeed = avatarSeed
            return
        }
        preferences.leaderboardAvatarSeed = LeaderboardAvatarSeed.random()
    }

    private func saveCurrentProfileIfPossible() async {
        guard !isSavingProfile else { return }

        let nickname = preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            syncStatus = .needsNickname
            return
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        syncStatus = .checkingAccount
        accountState = await client.accountState()
        guard accountState == .available else {
            let reason = accountState.displayText
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            return
        }

        syncStatus = .syncing
        do {
            let profile = try await client.saveProfile(LeaderboardProfileDraft(
                nickname: nickname,
                avatarSeed: ensureLocalAvatarSeed()
            ))
            remember(profile: profile)
            preferences.leaderboardLastSyncError = ""
            syncStatus = statusAfterAccountCheck()
        } catch {
            let reason = userFacingMessage(error)
            preferences.leaderboardLastSyncError = reason
            syncStatus = .failed(reason)
            Log.network.error("Leaderboard profile save failed: \(reason, privacy: .public)")
        }
    }

    private func remember(profile: LeaderboardProfile) {
        currentUserHash = profile.userHash
        preferences.leaderboardProfileUserHash = profile.userHash
        if let avatarSeed = profile.avatarSeed,
           !avatarSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.leaderboardAvatarSeed = avatarSeed
        }
    }

    private func statusAfterAccountCheck() -> SyncStatus {
        if preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .needsNickname
        }
        if let last = preferences.leaderboardLastSyncedAt {
            return .synced(last)
        }
        return accountState == .available ? .idle : .failed(accountState.displayText)
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let error = error as? LeaderboardCloudError {
            return error.description
        }
        return error.localizedDescription
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
