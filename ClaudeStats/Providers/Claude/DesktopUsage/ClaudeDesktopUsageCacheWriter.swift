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
        let mergedSnapshot = snapshotByMergingFreshExistingWindows(into: snapshot)
        Log.app.debug(
            "Writing Claude Desktop usage cache; incoming=\(windowIDs(snapshot.windows), privacy: .public), merged=\(windowIDs(mergedSnapshot.windows), privacy: .public)"
        )
        let data = try JSONSerialization.data(withJSONObject: payload(for: mergedSnapshot), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: cacheURL, options: .atomic)
    }

    private func snapshotByMergingFreshExistingWindows(into snapshot: UsageLimitSnapshot) -> UsageLimitSnapshot {
        guard let existing = existingFreshSnapshot(now: snapshot.capturedAt) else {
            return snapshot
        }

        var windowsByID = Dictionary(uniqueKeysWithValues: existing.windows.map { ($0.id, $0) })
        for window in snapshot.windows {
            windowsByID[window.id] = window
        }

        return UsageLimitSnapshot(
            provider: snapshot.provider,
            windows: UsageLimitWindowCatalog.orderedClaudeWindows(Array(windowsByID.values)),
            capturedAt: snapshot.capturedAt,
            sourceLabel: snapshot.sourceLabel,
            sourcePath: snapshot.sourcePath,
            planType: snapshot.planType,
            limitID: snapshot.limitID
        )
    }

    private func existingFreshSnapshot(now: Date) -> UsageLimitSnapshot? {
        let report = ClaudeUsageLimitLoader(
            paths: .default,
            cacheURLs: [cacheURL]
        ).report(now: now, fileManager: fileManager)

        guard report.status == .fresh else { return nil }
        return report.snapshot
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

    private func windowIDs(_ windows: [UsageLimitWindow]) -> String {
        windows.map(\.id).joined(separator: ",")
    }
}
