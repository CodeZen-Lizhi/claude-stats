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

    @Test("Parses OpenComputerUse snapshot text")
    func parsesOpenComputerUseSnapshotText() throws {
        let snapshot = try #require(parser.snapshot(
            from: """
            App=com.anthropic.claudefordesktop (pid 123)
            Window: "Claude", App: Claude.
            0 window Claude
                12 button Usage limits
                13 text 5h
                14 text 94% left
                15 text 6% used
                16 text weekly
                17 text 3% used
            """
        ))

        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(snapshot.windows.map(\.usedPercent) == [6, 3])
    }

    @Test("Parses Claude Desktop Plan usage popover")
    func parsesClaudeDesktopPlanUsagePopover() throws {
        let snapshot = try #require(parser.snapshot(
            from: """
            Plan usage
            5-hour limit
            0%
            Weekly · all models
            1%
            Weekly · Claude Design
            2%
            Sonnet only
            3%
            """
        ))

        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day", "weekly_claude_design", "sonnet_only"])
        #expect(snapshot.windows.map(\.usedPercent) == [0, 1, 2, 3])
    }

    @Test("Parses marker variants and treats bare percent as used")
    func parsesMarkerVariantsAndBarePercent() throws {
        let hyphenated = try #require(parser.snapshot(from: "5-hour limit\n11%\nWeekly - all models\n22%"))
        #expect(hyphenated.windows.map(\.usedPercent) == [11, 22])

        let spaced = try #require(parser.snapshot(from: "5 hour limit\n33%\nWeekly · all models\n44%"))
        #expect(spaced.windows.map(\.usedPercent) == [33, 44])

        let compact = try #require(parser.snapshot(from: "5h limit\n55%\n7d\n66%"))
        #expect(compact.windows.map(\.usedPercent) == [55, 66])

        let nonBreakingHyphen = try #require(parser.snapshot(from: "5‑hour limit\n12%\nWeekly ‑ all models\n34%"))
        #expect(nonBreakingHyphen.windows.map(\.usedPercent) == [12, 34])
    }

    @Test("Clamps usage percentages and allows missing reset")
    func clampsAndAllowsMissingReset() throws {
        let snapshot = try #require(parser.snapshot(from: "5h\n140% used"))
        let window = try #require(snapshot.windows.first)

        #expect(window.usedPercent == 100)
        #expect(window.resetAt == nil)
        #expect(window.remainingPercent == 0)
    }

    @Test("Remaining percent keeps semantic precedence over bare percent")
    func remainingPercentKeepsSemanticPrecedence() throws {
        let snapshot = try #require(parser.snapshot(from: "5-hour limit\n94% left"))
        let window = try #require(snapshot.windows.first)

        #expect(window.usedPercent == 6)
    }

    @Test("Invalid OCR text does not produce a snapshot")
    func invalidTextProducesNoSnapshot() {
        #expect(parser.snapshot(from: "Claude Desktop\nProjects\nSettings") == nil)
    }
}
