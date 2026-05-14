import Foundation

/// Classifies each day in `range` against the Local and GitHub heatmaps and
/// reports two alignment scores: Jaccard (binary active/not active) for the
/// headline percentage, and Pearson (intensity correlation) for the secondary
/// hover label.
///
/// A day is "active" for a series when its `value > 0`. Days are aligned by
/// `Date` key — both series use `Calendar.current.startOfDay(for:)`.
struct OverlapStats: Sendable, Hashable {
    enum DayState: String, Sendable, Hashable, CaseIterable {
        case neither, localOnly, githubOnly, both
    }

    let byDay: [Date: DayState]
    let bothCount: Int
    let localOnlyCount: Int
    let githubOnlyCount: Int
    let neitherCount: Int
    /// `|both| / (|both| + |localOnly| + |githubOnly|)`. Zero when both
    /// series are empty.
    let jaccard: Double
    /// Pearson correlation across daily values over `range`. `nil` when
    /// either series is constant (sd = 0) — UI hides the secondary line.
    let pearson: Double?

    /// Pure value-type computation. Cheap (linear in `range.dayCount`); safe
    /// to call from any actor.
    static func compute(
        local: [HeatmapCell],
        github: [HeatmapCell],
        range: DateInterval,
        calendar: Calendar = .current
    ) -> OverlapStats {
        let localByDay = Dictionary(uniqueKeysWithValues: local.map { ($0.date, $0.value) })
        let githubByDay = Dictionary(uniqueKeysWithValues: github.map { ($0.date, $0.value) })

        var byDay: [Date: DayState] = [:]
        var both = 0, localOnly = 0, githubOnly = 0, neither = 0
        var localSeries: [Double] = []
        var githubSeries: [Double] = []

        var cursor = calendar.startOfDay(for: range.start)
        let endExclusive = range.end
        while cursor < endExclusive {
            let l = localByDay[cursor] ?? 0
            let g = githubByDay[cursor] ?? 0
            let state: DayState
            switch (l > 0, g > 0) {
            case (true, true):  state = .both;        both += 1
            case (true, false): state = .localOnly;   localOnly += 1
            case (false, true): state = .githubOnly;  githubOnly += 1
            case (false, false):state = .neither;     neither += 1
            }
            byDay[cursor] = state
            localSeries.append(Double(l))
            githubSeries.append(Double(g))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        let union = both + localOnly + githubOnly
        let jaccard = union > 0 ? Double(both) / Double(union) : 0
        let pearson = correlation(localSeries, githubSeries)

        return OverlapStats(
            byDay: byDay,
            bothCount: both,
            localOnlyCount: localOnly,
            githubOnlyCount: githubOnly,
            neitherCount: neither,
            jaccard: jaccard,
            pearson: pearson
        )
    }

    /// Sample Pearson correlation; `nil` when either series has zero variance
    /// or the sample sizes don't match.
    private static func correlation(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 1 else { return nil }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var num = 0.0, denX = 0.0, denY = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0 && denY > 0 else { return nil }
        return num / (denX.squareRoot() * denY.squareRoot())
    }
}
