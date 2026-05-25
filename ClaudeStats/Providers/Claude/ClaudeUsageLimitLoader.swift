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
            guard let selection = try latestSnapshot(now: now, fileManager: fileManager) else {
                return .setupRequired(
                    provider: .claude,
                    message: "Connect Claude Code's status line to let Claude Stats capture 5h and weekly limits."
                )
            }
            switch selection {
            case .fresh(let snapshot):
                return .fresh(provider: .claude, snapshot: snapshot)
            case .stale(let snapshot):
                return .cached(provider: .claude, snapshot: snapshot)
            }
        } catch {
            return .unavailable(provider: .claude, message: "Could not read Claude usage limits: \(error.localizedDescription)")
        }
    }

    private func latestSnapshot(now: Date, fileManager: FileManager) throws -> SnapshotSelection? {
        let candidates = cacheURLs
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map { url -> (url: URL, modifiedAt: Date) in
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        var parsedCandidates: [ParsedCandidate] = []
        for candidate in candidates {
            if let snapshot = try snapshot(from: candidate.url, capturedAt: candidate.modifiedAt) {
                parsedCandidates.append(ParsedCandidate(url: candidate.url, modifiedAt: candidate.modifiedAt, snapshot: snapshot))
            }
        }
        guard !parsedCandidates.isEmpty else { return nil }

        if let fresh = mergedFreshSnapshot(from: parsedCandidates, now: now) {
            return .fresh(fresh)
        }

        return .stale(parsedCandidates[0].snapshot)
    }

    private func snapshot(from url: URL, capturedAt: Date) throws -> UsageLimitSnapshot? {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return nil }
        let payload = (dictionary["rate_limits"] as? [String: Any]) ?? dictionary
        let windows = UsageLimitWindowCatalog.claudeWindowDefinitions.compactMap { definition in
            usageWindow(definition: definition, in: payload)
        }
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

    private func usageWindow(definition: UsageLimitWindowMetadata, in payload: [String: Any]) -> UsageLimitWindow? {
        guard let raw = payload[definition.id] as? [String: Any],
              let usedPercent = UsageLimitDecoding.number(from: raw["used_percentage"])
                ?? UsageLimitDecoding.number(from: raw["utilization"]) else {
            return nil
        }
        return UsageLimitWindow(
            id: definition.id,
            label: definition.label,
            usedPercent: usedPercent,
            resetAt: UsageLimitDecoding.date(from: raw["resets_at"]),
            windowMinutes: definition.minutes
        )
    }

    private func mergedFreshSnapshot(from candidates: [ParsedCandidate], now: Date) -> UsageLimitSnapshot? {
        var windowsByID: [String: UsageLimitWindow] = [:]
        var latestCandidate: ParsedCandidate?

        for candidate in candidates {
            guard now.timeIntervalSince(candidate.modifiedAt) <= Self.snapshotTTL else { continue }
            for window in candidate.snapshot.windows where isFresh(window: window, now: now) {
                guard windowsByID[window.id] == nil else { continue }
                windowsByID[window.id] = window
                if latestCandidate == nil || candidate.modifiedAt > (latestCandidate?.modifiedAt ?? .distantPast) {
                    latestCandidate = candidate
                }
            }
        }

        let windows = UsageLimitWindowCatalog.orderedClaudeWindows(Array(windowsByID.values))
        guard !windows.isEmpty, let latestCandidate else { return nil }
        return UsageLimitSnapshot(
            provider: .claude,
            windows: windows,
            capturedAt: latestCandidate.modifiedAt,
            sourceLabel: latestCandidate.snapshot.sourceLabel,
            sourcePath: latestCandidate.url.path,
            planType: nil,
            limitID: nil
        )
    }

    private func isFresh(window: UsageLimitWindow, now: Date) -> Bool {
        guard let resetAt = window.resetAt else { return true }
        return resetAt > now
    }

    private func sourceLabel(for url: URL, payload: [String: Any]) -> String {
        if payload["source"] as? String == "claude_desktop_ui" {
            return "Claude Desktop UI"
        }
        if payload["source"] as? String == "claude_statusline" {
            return "Claude Code status line"
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

    private struct ParsedCandidate {
        let url: URL
        let modifiedAt: Date
        let snapshot: UsageLimitSnapshot
    }

    private enum SnapshotSelection {
        case fresh(UsageLimitSnapshot)
        case stale(UsageLimitSnapshot)
    }
}
