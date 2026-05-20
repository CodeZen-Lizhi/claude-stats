import Foundation

protocol ClaudeDesktopUsageCacheWriting {
    func write(_ snapshot: UsageLimitSnapshot) throws
}

struct ClaudeDesktopUsageCacheWriter: ClaudeDesktopUsageCacheWriting {
    let cacheURL: URL
    private let fileManager: FileManager

    init(cacheURL: URL = UsageLimitCachePaths.claudeCacheURL(), fileManager: FileManager = .default) {
        self.cacheURL = cacheURL
        self.fileManager = fileManager
    }

    func write(_ snapshot: UsageLimitSnapshot) throws {
        guard !snapshot.windows.isEmpty else { return }
        try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: payload(for: snapshot), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: cacheURL, options: .atomic)
    }

    private func payload(for snapshot: UsageLimitSnapshot) -> [String: Any] {
        var rateLimits: [String: Any] = [:]
        for window in snapshot.windows {
            var windowPayload: [String: Any] = [
                "used_percentage": window.clampedUsedPercent,
            ]
            if let resetAt = window.resetAt {
                windowPayload["resets_at"] = resetAt.formatted(.iso8601)
            }
            rateLimits[window.id] = windowPayload
        }

        return [
            "source": "claude_desktop_ui",
            "captured_at": snapshot.capturedAt.formatted(.iso8601),
            "rate_limits": rateLimits,
        ]
    }
}
