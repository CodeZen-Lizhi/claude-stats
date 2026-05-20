import AppKit

@MainActor
protocol LeaderboardRemoteNotificationRegistering: AnyObject {
    func registerForLeaderboardRemoteNotifications()
}

@MainActor
final class AppKitLeaderboardRemoteNotificationRegistrar: LeaderboardRemoteNotificationRegistering {
    func registerForLeaderboardRemoteNotifications() {
        NSApplication.shared.registerForRemoteNotifications()
    }
}
