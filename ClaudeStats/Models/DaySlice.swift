import Foundation

/// One day's worth of token usage, used for the usage trend chart.
struct DaySlice: Sendable, Hashable, Identifiable {
    /// Start of the day (local calendar).
    let day: Date
    let usage: TokenUsage

    var id: Date { day }
    var tokens: Int { usage.total }
}

extension Array where Element == DaySlice {
    /// Merge slices that fall on the same day, then sort ascending.
    func mergedByDay() -> [DaySlice] {
        var byDay: [Date: TokenUsage] = [:]
        for slice in self { byDay[slice.day, default: .zero] += slice.usage }
        return byDay
            .map { DaySlice(day: $0.key, usage: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
