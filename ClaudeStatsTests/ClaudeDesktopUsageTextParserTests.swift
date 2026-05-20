import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude Desktop usage text parser")
struct ClaudeDesktopUsageTextParserTests {
    private let parser = ClaudeDesktopUsageTextParser()

    @Test("Parses English 5h and weekly usage text")
    func parsesEnglishUsageText() throws {
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-05-20T08:00:00.000Z")
        let snapshot = try #require(parser.snapshot(
            from: """
            Usage limits
            5h
            94% left
            6% used
            Resets in 4h
            7D
            97% left
            3% used
            Resets in 6d
            """,
            capturedAt: now
        ))

        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(snapshot.windows[0].usedPercent == 6)
        #expect(snapshot.windows[1].usedPercent == 3)
        #expect(snapshot.windows[0].resetAt?.timeIntervalSince(now) == 14_400)
        #expect(snapshot.windows[1].resetAt?.timeIntervalSince(now) == 518_400)
    }

    @Test("Parses Chinese remaining and used usage text")
    func parsesChineseUsageText() throws {
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-05-20T08:00:00.000Z")
        let snapshot = try #require(parser.snapshot(
            from: """
            用量限制
            5 小时
            剩余 94%
            4小时后重置
            每周
            已用 20%
            6天后重置
            """,
            capturedAt: now
        ))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].usedPercent == 6)
        #expect(snapshot.windows[1].usedPercent == 20)
    }

    @Test("Clamps usage percentages and allows missing reset")
    func clampsAndAllowsMissingReset() throws {
        let snapshot = try #require(parser.snapshot(from: "5h\n140% used"))
        let window = try #require(snapshot.windows.first)

        #expect(window.usedPercent == 100)
        #expect(window.resetAt == nil)
        #expect(window.remainingPercent == 0)
    }

    @Test("Invalid OCR text does not produce a snapshot")
    func invalidTextProducesNoSnapshot() {
        #expect(parser.snapshot(from: "Claude Desktop\nProjects\nSettings") == nil)
    }
}
