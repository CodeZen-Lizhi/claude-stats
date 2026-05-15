import Testing
import Foundation
@testable import ClaudeStats

@Suite("OverlapStats")
struct OverlapStatsTests {
    private let cal = Calendar.current

    private func day(_ offset: Int, from anchor: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: anchor))!
    }

    private func makeRange(daysBack: Int, anchor: Date) -> DateInterval {
        let start = cal.date(byAdding: .day, value: -(daysBack - 1), to: cal.startOfDay(for: anchor))!
        let end = cal.dateInterval(of: .day, for: anchor)!.end
        return DateInterval(start: start, end: end)
    }

    @Test("Jaccard counts active-day overlap correctly")
    func jaccardOverlap() {
        let anchor = Date.now
        let range = makeRange(daysBack: 7, anchor: anchor)

        // Days 0,1,2,3 local-active. Days 1,2 GitHub-active. (Day=0 means today.)
        let local: [HeatmapCell] = [
            HeatmapCell(date: day(0, from: anchor), value: 1),
            HeatmapCell(date: day(-1, from: anchor), value: 2),
            HeatmapCell(date: day(-2, from: anchor), value: 1),
            HeatmapCell(date: day(-3, from: anchor), value: 5),
        ]
        let github: [HeatmapCell] = [
            HeatmapCell(date: day(-1, from: anchor), value: 1),
            HeatmapCell(date: day(-2, from: anchor), value: 3),
            HeatmapCell(date: day(-5, from: anchor), value: 2),
        ]
        let stats = OverlapStats.compute(local: local, github: github, range: range)

        // Both = days -1, -2 → 2
        #expect(stats.bothCount == 2)
        // Local only = days 0, -3 → 2
        #expect(stats.localOnlyCount == 2)
        // GitHub only = day -5 → 1
        #expect(stats.githubOnlyCount == 1)
        // Neither = days -4, -6 → 2
        #expect(stats.neitherCount == 2)
        // Union = 5, intersection = 2 → 0.4
        #expect(abs(stats.jaccard - 0.4) < 1e-9)
    }

    @Test("Empty inputs yield zero alignment and all neither")
    func emptyInputs() {
        let anchor = Date.now
        let range = makeRange(daysBack: 5, anchor: anchor)
        let stats = OverlapStats.compute(local: [], github: [], range: range)
        #expect(stats.bothCount == 0)
        #expect(stats.localOnlyCount == 0)
        #expect(stats.githubOnlyCount == 0)
        #expect(stats.neitherCount == 5)
        #expect(stats.jaccard == 0)
        #expect(stats.pearson == nil)
    }

    @Test("Pearson is nil when either series is constant")
    func pearsonConstantSeries() {
        let anchor = Date.now
        let range = makeRange(daysBack: 4, anchor: anchor)
        let local: [HeatmapCell] = (0..<4).map { i in
            HeatmapCell(date: day(-i, from: anchor), value: i + 1)
        }
        // GitHub series is all-zero — constant.
        let stats = OverlapStats.compute(local: local, github: [], range: range)
        #expect(stats.pearson == nil)
    }

    @Test("Pearson is ~+1 when series move together")
    func pearsonPerfectPositive() throws {
        let anchor = Date.now
        let range = makeRange(daysBack: 5, anchor: anchor)
        let values = [1, 2, 3, 4, 5]
        let local = values.enumerated().map { idx, v in
            HeatmapCell(date: day(-idx, from: anchor), value: v)
        }
        let github = values.enumerated().map { idx, v in
            HeatmapCell(date: day(-idx, from: anchor), value: v * 3)
        }
        let stats = OverlapStats.compute(local: local, github: github, range: range)
        let r = try #require(stats.pearson)
        #expect(abs(r - 1.0) < 1e-9)
    }
}
