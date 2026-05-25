import Foundation

enum UsageLimitStatus: String, Codable, Sendable, Hashable {
    case fresh
    case setupRequired
    case waitingForNextResponse
    case unavailable
    case unsupported
}

struct UsageLimitReport: Codable, Sendable, Hashable {
    let provider: ProviderKind
    let status: UsageLimitStatus
    let snapshot: UsageLimitSnapshot?
    let message: String?

    var lastCapturedAt: Date? { snapshot?.capturedAt }

    static func fresh(provider: ProviderKind, snapshot: UsageLimitSnapshot) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .fresh, snapshot: snapshot, message: nil)
    }

    static func setupRequired(provider: ProviderKind, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .setupRequired, snapshot: nil, message: message)
    }

    static func waitingForNextResponse(provider: ProviderKind, snapshot: UsageLimitSnapshot?, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .waitingForNextResponse, snapshot: snapshot, message: message)
    }

    static func unavailable(provider: ProviderKind, message: String) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .unavailable, snapshot: nil, message: message)
    }

    static func unsupported(provider: ProviderKind) -> UsageLimitReport {
        UsageLimitReport(provider: provider, status: .unsupported, snapshot: nil, message: nil)
    }
}

struct UsageLimitSnapshot: Codable, Sendable, Hashable {
    let provider: ProviderKind
    let windows: [UsageLimitWindow]
    let capturedAt: Date
    let sourceLabel: String
    let sourcePath: String?
    let planType: String?
    let limitID: String?

    var isEmpty: Bool { windows.isEmpty }

    func isFresh(now: Date, ttl: TimeInterval) -> Bool {
        guard now.timeIntervalSince(capturedAt) <= ttl else { return false }
        return windows.allSatisfy { window in
            guard let resetAt = window.resetAt else { return true }
            return resetAt > now
        }
    }
}

struct UsageLimitWindow: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Date?
    let windowMinutes: Int?

    var clampedUsedPercent: Double {
        min(100, max(0, usedPercent))
    }

    var remainingPercent: Double {
        100 - clampedUsedPercent
    }
}

extension ProviderKind {
    var supportsUsageLimits: Bool {
        true
    }
}
