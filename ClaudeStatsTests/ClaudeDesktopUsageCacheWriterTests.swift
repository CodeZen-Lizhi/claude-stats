import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude Desktop usage cache writer")
struct ClaudeDesktopUsageCacheWriterTests {
    @Test("Writes cache that Claude loader reads as Desktop UI source")
    func writesReadableDesktopCache() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("claude-rate-limits.json")
        let now = Date()
        let snapshot = UsageLimitSnapshot(
            provider: .claude,
            windows: [
                UsageLimitWindow(id: "five_hour", label: "5h", usedPercent: 6, resetAt: now.addingTimeInterval(3_600), windowMinutes: 300),
                UsageLimitWindow(id: "seven_day", label: "7d", usedPercent: 3, resetAt: now.addingTimeInterval(86_400), windowMinutes: 10_080),
            ],
            capturedAt: now,
            sourceLabel: "Claude Desktop UI",
            sourcePath: cache.path,
            planType: nil,
            limitID: "claude-desktop-ui"
        )

        try ClaudeDesktopUsageCacheWriter(cacheURL: cache).write(snapshot)
        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [cache]
        ).report(now: now)

        #expect(report.status == .fresh)
        #expect(report.snapshot?.sourceLabel == "Claude Desktop UI")
        #expect(report.snapshot?.windows.map(\.usedPercent) == [6, 3])
    }

    @Test("Merges fresh existing windows when writing partial Desktop snapshot")
    func mergesFreshExistingWindowsWhenWritingPartialSnapshot() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("claude-rate-limits.json")
        let now = Date()
        try TempDir.write(#"{"five_hour":{"used_percentage":6}}"#, to: cache)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: cache.path)

        let snapshot = UsageLimitSnapshot(
            provider: .claude,
            windows: [
                UsageLimitWindow(id: "seven_day", label: "7d", usedPercent: 3, resetAt: nil, windowMinutes: 10_080),
            ],
            capturedAt: now,
            sourceLabel: "Claude Desktop UI",
            sourcePath: cache.path,
            planType: nil,
            limitID: "claude-desktop-ui"
        )

        try ClaudeDesktopUsageCacheWriter(cacheURL: cache).write(snapshot)

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [cache]
        ).report(now: now)

        #expect(report.snapshot?.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(report.snapshot?.windows.map(\.usedPercent) == [6, 3])
    }

    @Test("Does not preserve stale existing windows when writing partial Desktop snapshot")
    func skipsStaleExistingWindowsWhenWritingPartialSnapshot() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("claude-rate-limits.json")
        let now = Date()
        try TempDir.write(#"{"five_hour":{"used_percentage":6}}"#, to: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-ClaudeUsageLimitLoader.snapshotTTL - 60)],
            ofItemAtPath: cache.path
        )

        let snapshot = UsageLimitSnapshot(
            provider: .claude,
            windows: [
                UsageLimitWindow(id: "seven_day", label: "7d", usedPercent: 3, resetAt: nil, windowMinutes: 10_080),
            ],
            capturedAt: now,
            sourceLabel: "Claude Desktop UI",
            sourcePath: cache.path,
            planType: nil,
            limitID: "claude-desktop-ui"
        )

        try ClaudeDesktopUsageCacheWriter(cacheURL: cache).write(snapshot)

        let report = ClaudeUsageLimitLoader(
            paths: ClaudePaths(configDirectory: root),
            cacheURLs: [cache]
        ).report(now: now)

        #expect(report.snapshot?.windows.map(\.id) == ["seven_day"])
    }
}
