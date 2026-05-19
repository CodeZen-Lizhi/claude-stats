import AtollEmbed
import Testing

@Suite("AtollDefaultsBridge")
struct AtollDefaultsBridgeTests {
    @Test("Recommended width follows Atoll tab count thresholds")
    func recommendedWidthFollowsTabThresholds() {
        #expect(AtollDefaultsBridge.standardTabCount(for: [.media]) == 1)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: [.media]) == 640)

        let fiveTabs: Set<AtollIslandFeature> = [.media, .shelf, .timer, .stats, .clipboard]
        #expect(AtollDefaultsBridge.standardTabCount(for: fiveTabs) == 5)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: fiveTabs) == 690)

        let sixTabs = fiveTabs.union([.terminal])
        #expect(AtollDefaultsBridge.standardTabCount(for: sixTabs) == 6)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: sixTabs) == 770)
    }

    @Test("Resolved width never undercuts Atoll recommendation")
    func resolvedWidthDoesNotUndercutRecommendation() {
        let sixTabs: Set<AtollIslandFeature> = [.media, .shelf, .timer, .stats, .clipboard, .terminal]

        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 420,
                features: sixTabs,
                maxAllowedWidth: 900
            ) == 770
        )
        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 840,
                features: sixTabs,
                maxAllowedWidth: 900
            ) == 840
        )
        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 840,
                features: sixTabs,
                maxAllowedWidth: 700
            ) == 700
        )
    }
}
