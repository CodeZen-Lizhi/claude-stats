import CloudKit
import Foundation

protocol LeaderboardRealtimeCloudServicing: Sendable {
    func ensureSubscription() async throws
    func deleteManagedSubscriptions(except subscriptionIDs: Set<String>) async
}

struct CloudKitLeaderboardSubscriptionClient: LeaderboardRealtimeCloudServicing {
    private let containerIdentifier: String
    private let entitlementChecker: @Sendable (String) -> Bool

    init(
        containerIdentifier: String = CloudKitLeaderboardConfig.containerIdentifier,
        entitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess
    ) {
        self.containerIdentifier = containerIdentifier
        self.entitlementChecker = entitlementChecker
    }

    func ensureSubscription() async throws {
        try ensureCloudKitEntitlement()
        let subscription = CKQuerySubscription(
            recordType: CloudKitLeaderboardConfig.recordType,
            predicate: Self.subscriptionPredicate(),
            subscriptionID: LeaderboardRealtimeNotification.globalSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        subscription.notificationInfo = CKSubscription.NotificationInfo(shouldSendContentAvailable: true)

        do {
            let result = try await publicDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            if case .failure(let error) = result.saveResults[LeaderboardRealtimeNotification.globalSubscriptionID] {
                throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
            }
        } catch let error as LeaderboardCloudError {
            throw error
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    func deleteManagedSubscriptions(except subscriptionIDs: Set<String>) async {
        guard entitlementChecker(containerIdentifier) else { return }
        do {
            let subscriptions = try await publicDatabase.allSubscriptions()
            let idsToDelete = subscriptions
                .map(\.subscriptionID)
                .filter { LeaderboardRealtimeNotification.isManagedSubscriptionID($0) }
                .filter { !subscriptionIDs.contains($0) }

            guard !idsToDelete.isEmpty else { return }
            _ = try await publicDatabase.modifySubscriptions(saving: [], deleting: idsToDelete)
        } catch {
            Log.network.debug("Leaderboard subscription cleanup failed: \(Self.shortCloudKitMessage(error), privacy: .public)")
        }
    }

    static func subscriptionPredicate() -> NSPredicate {
        NSPredicate(
            format: "%K == %@",
            CloudKitLeaderboardRecordMapper.Field.providerScope, CloudKitLeaderboardConfig.providerScope
        )
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
