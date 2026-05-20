import Foundation

struct ClaudeUsageLimitLoader: Sendable {
    let paths: ClaudePaths
    let cacheURLs: [URL]

    static let snapshotTTL: TimeInterval = 30 * 60

    init(paths: ClaudePaths, cacheURLs: [URL]? = nil) {
        self.paths = paths
        self.cacheURLs = cacheURLs ?? [
            UsageLimitCachePaths.claudeCacheURL(),
            URL(fileURLWithPath: "/tmp/open-island-rl.json", isDirectory: false),
            URL(fileURLWithPath: "/tmp/vibe-island-rl.json", isDirectory: false),
        ]
    }

    func report(now: Date = .now, fileManager: FileManager = .default) -> UsageLimitReport {
        do {
            guard let snapshot = try latestSnapshot(fileManager: fileManager) else {
                return .setupRequired(
                    provider: .claude,
                    message: "Connect Claude Code's status line to let Claude Stats capture 5h and weekly limits."
                )
            }
            guard snapshot.isFresh(now: now, ttl: Self.snapshotTTL) else {
                return .waitingForNextResponse(
                    provider: .claude,
                    snapshot: snapshot,
                    message: "Claude usage limits will refresh after the next Claude Code response."
                )
            }
            return .fresh(provider: .claude, snapshot: snapshot)
        } catch {
            return .unavailable(provider: .claude, message: "Could not read Claude usage limits: \(error.localizedDescription)")
        }
    }

    private func latestSnapshot(fileManager: FileManager) throws -> UsageLimitSnapshot? {
        let candidates = cacheURLs
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map { url -> (url: URL, modifiedAt: Date) in
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        for candidate in candidates {
            if let snapshot = try snapshot(from: candidate.url, capturedAt: candidate.modifiedAt) {
                return snapshot
            }
        }
        return nil
    }

    private func snapshot(from url: URL, capturedAt: Date) throws -> UsageLimitSnapshot? {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return nil }
        let payload = (dictionary["rate_limits"] as? [String: Any]) ?? dictionary
        let windows = [
            usageWindow(id: "five_hour", label: "5h", minutes: 300, in: payload),
            usageWindow(id: "seven_day", label: "7d", minutes: 10_080, in: payload),
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        return UsageLimitSnapshot(
            provider: .claude,
            windows: windows,
            capturedAt: capturedAt,
            sourceLabel: sourceLabel(for: url, payload: dictionary),
            sourcePath: url.path,
            planType: nil,
            limitID: nil
        )
    }

    private func usageWindow(id: String, label: String, minutes: Int, in payload: [String: Any]) -> UsageLimitWindow? {
        guard let raw = payload[id] as? [String: Any],
              let usedPercent = UsageLimitDecoding.number(from: raw["used_percentage"])
                ?? UsageLimitDecoding.number(from: raw["utilization"]) else {
            return nil
        }
        return UsageLimitWindow(
            id: id,
            label: label,
            usedPercent: usedPercent,
            resetAt: UsageLimitDecoding.date(from: raw["resets_at"]),
            windowMinutes: minutes
        )
    }

    private func sourceLabel(for url: URL, payload: [String: Any]) -> String {
        if payload["source"] as? String == "claude_desktop_ui" {
            return "Claude Desktop UI"
        }
        return switch url.path {
        case UsageLimitCachePaths.claudeCacheURL().path:
            "Claude Stats cache"
        case "/tmp/open-island-rl.json":
            "Open Island cache"
        case "/tmp/vibe-island-rl.json":
            "Vibe Island cache"
        default:
            "Claude usage cache"
        }
    }
}
