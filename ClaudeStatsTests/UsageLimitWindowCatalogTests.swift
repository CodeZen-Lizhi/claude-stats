import Foundation
import Testing
@testable import ClaudeStats

@Suite("Usage limit window catalog")
struct UsageLimitWindowCatalogTests {
    @Test("Claude windows are ordered and filtered by visible IDs")
    func claudeWindowsAreOrderedAndFilteredByVisibleIDs() {
        let windows = [
            UsageLimitWindow(id: "sonnet_only", label: "Sonnet", usedPercent: 4, resetAt: nil, windowMinutes: 10_080),
            UsageLimitWindow(id: "seven_day", label: "7d", usedPercent: 2, resetAt: nil, windowMinutes: 10_080),
            UsageLimitWindow(id: "weekly_claude_design", label: "Claude Design", usedPercent: 3, resetAt: nil, windowMinutes: 10_080),
            UsageLimitWindow(id: "five_hour", label: "5h", usedPercent: 1, resetAt: nil, windowMinutes: 300),
        ]

        let defaultVisible = UsageLimitWindowCatalog.visibleClaudeWindows(
            windows,
            visibleWindowIDs: UsageLimitWindowCatalog.claudeDefaultVisibleWindowIDs
        )
        let expandedVisible = UsageLimitWindowCatalog.visibleClaudeWindows(
            windows,
            visibleWindowIDs: ["weekly_claude_design", "sonnet_only"]
        )

        #expect(defaultVisible.map(\.id) == ["five_hour", "seven_day"])
        #expect(expandedVisible.map(\.id) == ["five_hour", "seven_day", "weekly_claude_design", "sonnet_only"])
    }

    @Test("Claude core completeness requires 5h and 7d")
    func claudeCoreCompletenessRequiresFiveHourAndSevenDay() {
        let partial = [
            UsageLimitWindow(id: "seven_day", label: "7d", usedPercent: 2, resetAt: nil, windowMinutes: 10_080),
        ]
        let complete = partial + [
            UsageLimitWindow(id: "five_hour", label: "5h", usedPercent: 1, resetAt: nil, windowMinutes: 300),
        ]

        #expect(UsageLimitWindowCatalog.isClaudeCoreComplete(partial) == false)
        #expect(UsageLimitWindowCatalog.isClaudeCoreComplete(complete) == true)
    }
}
