import Foundation
import Testing
@testable import ClaudeStats

@Suite("Usage trend hover snapshot")
struct UsageTrendHoverSnapshotTests {
    @Test("Hover snapshot selects nearest date and totals visible series")
    func hoverSnapshotSelectsNearestDateAndTotalsVisibleSeries() {
        let day1 = Date(timeIntervalSince1970: 1_000)
        let day2 = Date(timeIntervalSince1970: 86_400 + 1_000)
        let series = TrendSeries(
            granularity: .day,
            models: ["gpt-5", "gpt-5-mini"],
            buckets: [
                ModelBucket(model: "gpt-5", start: day1, usage: TokenUsage(inputTokens: 100, outputTokens: 50)),
                ModelBucket(model: "gpt-5-mini", start: day1, usage: TokenUsage(inputTokens: 20, outputTokens: 10)),
                ModelBucket(model: "gpt-5", start: day2, usage: TokenUsage(inputTokens: 300, outputTokens: 100)),
            ]
        )
        let snapshot = UsageTrendChartSnapshot(
            series: series,
            rangeID: "test",
            style: .bar,
            useLog: false,
            stackByType: false,
            displayName: { $0 }
        )

        let hover = UsageTrendHoverSnapshot.make(near: day1.addingTimeInterval(120), in: snapshot)

        #expect(hover?.date == day1)
        #expect(hover?.totalTokens == 180)
        #expect(hover?.seriesSummary.contains("gpt-5") == true)
    }
}
