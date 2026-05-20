import Foundation

enum ClaudeDesktopUsageCaptureTrigger: String, Sendable, Hashable {
    case manual
    case visibleAutomatic
    case timedAutomatic

    var allowsActivation: Bool { self == .manual }
    var promptsForPermissions: Bool { self == .manual }
    var shouldShowUserMessage: Bool { self == .manual }
}

enum ClaudeDesktopUsageAutoMode: String, CaseIterable, Sendable, Identifiable {
    case off
    case visibleOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            L10n.string("usage.limit.desktop_auto.off", defaultValue: "Manual only")
        case .visibleOnly:
            L10n.string("usage.limit.desktop_auto.visible", defaultValue: "Auto if visible")
        }
    }
}

enum ClaudeDesktopUsagePermissionIssue: Sendable, Hashable {
    case accessibility
    case screenRecording
}

enum ClaudeDesktopUsageCaptureSkipReason: Sendable, Hashable {
    case appNotRunning
    case notVisible
    case notFrontmost
}

enum ClaudeDesktopUsageCaptureError: Error, Equatable, Sendable {
    case appNotFound
    case appNotRunning
    case accessibilityPermissionRequired
    case screenRecordingPermissionRequired
    case noUsageText
    case parseFailed
    case cacheWriteFailed(String)
    case captureFailed(String)

    var permissionIssue: ClaudeDesktopUsagePermissionIssue? {
        switch self {
        case .accessibilityPermissionRequired:
            .accessibility
        case .screenRecordingPermissionRequired:
            .screenRecording
        default:
            nil
        }
    }
}

extension ClaudeDesktopUsageCaptureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .appNotFound:
            "Claude Desktop is not installed."
        case .appNotRunning:
            "Open Claude Desktop, then try reading usage again."
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to read Claude Desktop usage."
        case .screenRecordingPermissionRequired:
            "Screen Recording permission is required for OCR fallback."
        case .noUsageText:
            "Could not find visible Claude Desktop usage text."
        case .parseFailed:
            "Could not parse Claude Desktop usage text."
        case .cacheWriteFailed(let message):
            "Could not save Claude Desktop usage: \(message)"
        case .captureFailed(let message):
            "Could not read Claude Desktop usage: \(message)"
        }
    }
}

enum ClaudeDesktopUsageCaptureOutcome: Sendable, Equatable {
    case captured(UsageLimitSnapshot)
    case skipped(ClaudeDesktopUsageCaptureSkipReason)
    case failed(ClaudeDesktopUsageCaptureError)
}

struct ClaudeDesktopAppState: Sendable, Equatable {
    let isInstalled: Bool
    let isRunning: Bool
    let isVisible: Bool
    let isFrontmost: Bool
    let processIdentifier: pid_t?
    let localizedName: String?

    static let missing = ClaudeDesktopAppState(
        isInstalled: false,
        isRunning: false,
        isVisible: false,
        isFrontmost: false,
        processIdentifier: nil,
        localizedName: nil
    )
}
