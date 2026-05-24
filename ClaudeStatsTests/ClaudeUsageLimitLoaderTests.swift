import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude usage-limit loader")
struct ClaudeUsageLimitLoaderTests {
    @Test("Parses app cache and legacy Open Island cache candidates")
    func parsesCacheCandidates() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let appCache = root.appendingPathComponent("claude-rate-limits.json")
        let legacy = root.appendingPathComponent("open-island-rl.json")
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        try TempDir.write(#"{"five_hour":{"used_percentage":14,"resets_at":1768100000}}"#, to: appCache)
        try TempDir.write(#"{"seven_day":{"used_percentage":2,"resets_at":1768100000}}"#, to: legacy)
        try Self.setModified(legacy, now.addingTimeInterval(-120))
        try Self.setModified(appCache, now.addingTimeInterval(-60))

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [legacy, appCache]
        ).report(now: now)

        #expect(report.status == .fresh)
        #expect(report.snapshot?.windows.map(\.label) == ["5h", "7d"])
        #expect(report.snapshot?.windows.map(\.remainingPercent) == [86, 98])
    }

    @Test("Parses full status-line envelope and utilization aliases")
    func parsesFullEnvelopeAndAliases() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("claude-rate-limits.json")
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        try TempDir.write(#"{"rate_limits":{"five_hour":{"utilization":"33","resets_at":"2026-01-10T10:00:00Z"},"seven_day":{"used_percentage":"12","resets_at":1768100000}}}"#, to: cache)
        try Self.setModified(cache, now.addingTimeInterval(-60))

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [cache]
        ).report(now: now)

        #expect(report.status == .fresh)
        let windows = try #require(report.snapshot?.windows)
        #expect(windows.count == 2)
        #expect(windows[0].usedPercent == 33)
        #expect(windows[1].usedPercent == 12)
    }

    @Test("Parses extended Claude Desktop UI windows")
    func parsesExtendedClaudeDesktopUIWindows() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("claude-rate-limits.json")
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        try TempDir.write(
            """
            {
              "source": "claude_desktop_ui",
              "rate_limits": {
                "five_hour": {"used_percentage": 1},
                "seven_day": {"used_percentage": 2},
                "weekly_claude_design": {"used_percentage": 3},
                "sonnet_only": {"used_percentage": 4}
              }
            }
            """,
            to: cache
        )
        try Self.setModified(cache, now.addingTimeInterval(-60))

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [cache]
        ).report(now: now)

        #expect(report.status == .fresh)
        let windows = try #require(report.snapshot?.windows)
        #expect(windows.map(\.id) == ["five_hour", "seven_day", "weekly_claude_design", "sonnet_only"])
        #expect(windows.map(\.label) == ["5h", "7d", "Claude Design", "Sonnet"])
        #expect(windows.map(\.usedPercent) == [1, 2, 3, 4])
    }

    @Test("Merges fresh windows across cache candidates by newest value")
    func mergesFreshWindowsAcrossCandidates() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let latest = root.appendingPathComponent("latest.json")
        let older = root.appendingPathComponent("older.json")
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        try TempDir.write(#"{"seven_day":{"used_percentage":2}}"#, to: latest)
        try TempDir.write(#"{"five_hour":{"used_percentage":14},"seven_day":{"used_percentage":99}}"#, to: older)
        try Self.setModified(latest, now.addingTimeInterval(-60))
        try Self.setModified(older, now.addingTimeInterval(-120))

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [older, latest]
        ).report(now: now)

        let windows = try #require(report.snapshot?.windows)
        #expect(report.status == .fresh)
        #expect(windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(windows.map(\.usedPercent) == [14, 2])
    }

    @Test("Does not merge expired older windows")
    func skipsExpiredOlderWindowsWhenMerging() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let latest = root.appendingPathComponent("latest.json")
        let older = root.appendingPathComponent("older.json")
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:05:00.000Z")
        try TempDir.write(#"{"seven_day":{"used_percentage":2}}"#, to: latest)
        try TempDir.write(#"{"five_hour":{"used_percentage":14}}"#, to: older)
        try Self.setModified(latest, now.addingTimeInterval(-60))
        try Self.setModified(older, now.addingTimeInterval(-ClaudeUsageLimitLoader.snapshotTTL - 60))

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [older, latest]
        ).report(now: now)

        let windows = try #require(report.snapshot?.windows)
        #expect(report.status == .fresh)
        #expect(windows.map(\.id) == ["seven_day"])
    }

    @Test("Missing cache reports setup required")
    func missingCacheRequiresSetup() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [root.appendingPathComponent("missing.json")]
        ).report()

        #expect(report.status == .setupRequired)
        #expect(report.snapshot == nil)
    }

    private static func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
