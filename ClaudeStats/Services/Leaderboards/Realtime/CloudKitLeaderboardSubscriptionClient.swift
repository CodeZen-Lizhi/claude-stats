import CloudKit
import Foundation

protocol LeaderboardRealtimeCloudServicing: Sendable {
    func ensureSubscription(for scope: LeaderboardRealtimeScope) async throws
    func deleteManagedSubscriptions(except scopes: Set<LeaderboardRealtimeScope>) async
}

struct CloudKitLeaderboardSubscriptionClient: LeaderboardRealtimeCloudServicing {
    private let containerIdentifier: String
    private let entitlementChecker: @Sendable (String) -> Bool
    private let now: @Sendable () -> Date

    init(
        containerIdentifier: String = CloudKitLeaderboardConfig.containerIdentifier,
        entitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.containerIdentifier = containerIdentifier
        self.entitlementChecker = entitlementChecker
        self.now = now
    }

    func ensureSubscription(for scope: LeaderboardRealtimeScope) async throws {
        try ensureCloudKitEntitlement()
        let subscription = CKQuerySubscription(
            recordType: CloudKitLeaderboardConfig.recordType,
            predicate: Self.subscriptionPredicate(for: scope),
            subscriptionID: scope.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        subscription.notificationInfo = CKSubscription.NotificationInfo(shouldSendContentAvailable: true)

        do {
            let result = try await publicDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            if case .failure(let error) = result.saveResults[scope.subscriptionID] {
                throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
            }
        } catch let error as LeaderboardCloudError {
            throw error
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    func deleteManagedSubscriptions(except scopes: Set<LeaderboardRealtimeScope>) async {
        guard entitlementChecker(containerIdentifier) else { return }
        let idsToKeep = Set(scopes.map(\.subscriptionID))
        let idsToDelete = Self.managedLiveScopes(now: now())
            .map(\.subscriptionID)
            .filter { !idsToKeep.contains($0) }

        guard !idsToDelete.isEmpty else { return }
        do {
            _ = try await publicDatabase.modifySubscriptions(saving: [], deleting: idsToDelete)
        } catch {
            Log.network.debug("Leaderboard subscription cleanup failed: \(Self.shortCloudKitMessage(error), privacy: .public)")
        }
    }

    static func subscriptionPredicate(for scope: LeaderboardRealtimeScope) -> NSPredicate {
        NSPredicate(
            format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %@",
            CloudKitLeaderboardRecordMapper.Field.providerScope, CloudKitLeaderboardConfig.providerScope,
            CloudKitLeaderboardRecordMapper.Field.metric, scope.metric.rawValue,
            CloudKitLeaderboardRecordMapper.Field.period, scope.period.rawValue,
            CloudKitLeaderboardRecordMapper.Field.periodKey, scope.periodKey
        )
    }

    private static func managedLiveScopes(now: Date) -> [LeaderboardRealtimeScope] {
        LeaderboardMetric.allCases.flatMap { metric in
            LeaderboardPeriod.allCases.map { period in
                LeaderboardRealtimeScope.liveScope(metric: metric, period: period, now: now)
            }
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var publicDatabase: CKDatabase {
        container.publicCloudDatabase
    }

    private func ensureCloudKitEntitlement() throws {
        guard entitlementChecker(containerIdentifier) else {
            throw LeaderboardCloudError.missingEntitlement(Self.missingEntitlementMessage)
        }
    }

    private static let missingEntitlementMessage = "CloudKit entitlement is missing or incomplete in this build."

    private static func shortCloudKitMessage(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return LeaderboardCloudError.noAccount.description
            case .networkUnavailable, .networkFailure:
                return "Network unavailable."
            case .serviceUnavailable:
                return "CloudKit service unavailable."
            case .quotaExceeded:
                return "CloudKit quota exceeded."
            case .permissionFailure:
                return "CloudKit permission denied."
            case .serverRejectedRequest:
                return "CloudKit rejected the request."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
