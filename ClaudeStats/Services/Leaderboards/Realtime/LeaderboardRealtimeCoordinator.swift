import Foundation

actor LeaderboardRealtimeCoordinator {
    private let cloud: any LeaderboardRealtimeCloudServicing
    private let localStore: any LeaderboardLocalStoring
    private var didLoadState = false
    private var activeScope: LeaderboardRealtimeScope?
    private var pendingScopes: Set<LeaderboardRealtimeScope> = []
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
            try await cloud.ensureSubscription(for: scope)
            await cloud.deleteManagedSubscriptions(except: [scope])
            return pendingScopes.contains(scope) ? .pending : .live
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
        guard let scope = notification.scope else { return .ignored }

        lastNotificationAt = notification.receivedAt
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
        guard let scope, pendingScopes.remove(scope) != nil else { return false }
        await saveState()
        return true
    }

    func currentStatus(for scope: LeaderboardRealtimeScope?) async -> LeaderboardRealtimeStatus {
        await loadStateIfNeeded()
        guard let scope else { return .historicalCache }
        return pendingScopes.contains(scope) ? .pending : .live
    }

    private func loadStateIfNeeded() async {
        guard !didLoadState else { return }
        let state = await localStore.readRealtimeState()
        pendingScopes = state.pendingScopes
        lastNotificationAt = state.lastNotificationAt
        didLoadState = true
    }

    private func saveState() async {
        await localStore.writeRealtimeState(LeaderboardRealtimeState(
            pendingScopes: pendingScopes,
            lastNotificationAt: lastNotificationAt
        ))
    }
}
