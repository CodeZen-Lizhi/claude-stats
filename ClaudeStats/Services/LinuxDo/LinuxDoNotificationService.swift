import Foundation
import UserNotifications

enum LinuxDoNotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var canSendNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied, .unknown: false
        }
    }
}

protocol LinuxDoNotificationServicing: Sendable {
    func authorizationStatus() async -> LinuxDoNotificationAuthorizationStatus
    func requestAuthorization() async -> LinuxDoNotificationAuthorizationStatus
    func send(notification: LinuxDoNotification) async throws
}

struct LinuxDoNotificationService: LinuxDoNotificationServicing {
    func authorizationStatus() async -> LinuxDoNotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: Self.map(settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization() async -> LinuxDoNotificationAuthorizationStatus {
        let granted = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    Log.app.error("LinuxDo notification authorization failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: granted)
            }
        }
        if !granted {
            return await authorizationStatus()
        }
        return await authorizationStatus()
    }

    func send(notification: LinuxDoNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.displayTitle
        content.body = notification.displayBody.isEmpty ? "Open LinuxDo to view the update." : notification.displayBody
        content.sound = .default
        if let url = notification.topicURL {
            content.userInfo = ["url": url.absoluteString]
        }
        let request = UNNotificationRequest(
            identifier: "linuxdo-notification-\(notification.id)",
            content: content,
            trigger: nil
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> LinuxDoNotificationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unknown
        }
    }
}

