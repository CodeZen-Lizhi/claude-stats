import Foundation
import Testing
@testable import ClaudeStats

@Suite("Share card v2")
struct ShareCardV2Tests {
    @Test("Persona prefers session strategist for many sessions")
    func personaPrefersSessionStrategistForManySessions() {
        let summary = UsageSummary(
            period: .allTime,
            sessionCount: 24,
            models: [],
            messageCount: 100,
            timeline: []
        )

        #expect(SharePersona.choose(summary: summary).title == "Session Strategist")
    }

    @Test("Badges include fallback when usage is small")
    func badgesIncludeFallbackWhenUsageIsSmall() {
        let summary = UsageSummary.empty(period: .today)

        #expect(ShareBadge.make(summary: summary).map(\.id) == ["clean-start"])
    }
}
