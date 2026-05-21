import CloudKit
import Foundation

enum LeaderboardRemoteNotificationParser {
    static func notification(from userInfo: [AnyHashable: Any], receivedAt: Date = .now) -> LeaderboardRealtimeNotification? {
        guard let cloudNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let subscriptionID = cloudNotification.subscriptionID,
              LeaderboardRealtimeNotification.isManagedSubscriptionID(subscriptionID) else {
            return nil
        }
        return LeaderboardRealtimeNotification(subscriptionID: subscriptionID, receivedAt: receivedAt)
    }
}
