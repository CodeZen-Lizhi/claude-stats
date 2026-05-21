import Foundation

actor LeaderboardRealtimeCoordinator {
    private let cloud: any LeaderboardRealtimeCloudServicing
    private let localStore: any LeaderboardLocalStoring
    private var didLoadState = false
    private var activeScope: LeaderboardRealtimeScope?
    private var pendingScopes: Set<LeaderboardRealtimeScope> = []
    private var hasPendingGlobalChange = false
    private var lastNotificationAt: Date?

    init(
        cloud: any LeaderboardRealtimeCloudServicing = CloudKitLeaderboardSubscriptionClient(),
        localStore: any LeaderboardLocalStoring = LeaderboardLocalStore()
    ) {
        self.cloud = cloud
        self.localStore = localStore
    }

    func activate(scope: LeaderboardRealtimeScope?) async -> LeaderboardRealtimeStatus {
        await loadStateIfNeeded()
        activeScope = scope
        guard let scope else { return .historicalCache }

        do {
            try await cloud.ensureSubscription()
            await cloud.deleteManagedSubscriptions(except: [LeaderboardRealtimeNotification.globalSubscriptionID])
            return status(for: scope)
        } catch let error as LeaderboardCloudError {
            Log.network.error("Leaderboard realtime subscription failed: \(error.description, privacy: .public)")
            return .unavailable(error.description)
        } catch {
            Log.network.error("Leaderboard realtime subscription failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable(error.localizedDescription)
        }
    }

    func deactivate() {
        activeScope = nil
    }

    func handle(_ notification: LeaderboardRealtimeNotification) async -> LeaderboardRealtimeDecision {
        await loadStateIfNeeded()
        lastNotificationAt = notification.receivedAt

        if notification.isGlobalScoreChange {
            if let activeScope {
                await saveState()
                return .refresh(activeScope)
            }

            hasPendingGlobalChange = true
            await saveState()
            return .markedGlobalPending
        }

        guard let scope = notification.scope else { return .ignored }

        if scope == activeScope {
            await saveState()
            return .refresh(scope)
        }

        pendingScopes.insert(scope)
        await saveState()
        return .markedPending(scope)
    }

    func consumePending(for scope: LeaderboardRealtimeScope?) async -> Bool {
        await loadStateIfNeeded()
        guard let scope else { return false }

        let hadScopedPending = pendingScopes.remove(scope) != nil
        let hadGlobalPending = hasPendingGlobalChange
        guard hadScopedPending || hadGlobalPending else { return false }

        hasPendingGlobalChange = false
        await saveState()
        return true
    }

    func currentStatus(for scope: LeaderboardRealtimeScope?) async -> LeaderboardRealtimeStatus {
        await loadStateIfNeeded()
        guard let scope else { return .historicalCache }
        return status(for: scope)
    }

    private func loadStateIfNeeded() async {
        guard !didLoadState else { return }
        let state = await localStore.readRealtimeState()
        pendingScopes = state.pendingScopes
        lastNotificationAt = state.lastNotificationAt
        hasPendingGlobalChange = state.hasPendingGlobalChange
        didLoadState = true
    }

    private func saveState() async {
        await localStore.writeRealtimeState(LeaderboardRealtimeState(
            pendingScopes: pendingScopes,
            lastNotificationAt: lastNotificationAt,
            hasPendingGlobalChange: hasPendingGlobalChange
        ))
    }

    private func status(for scope: LeaderboardRealtimeScope) -> LeaderboardRealtimeStatus {
        pendingScopes.contains(scope) || hasPendingGlobalChange ? .pending : .live
    }
}
