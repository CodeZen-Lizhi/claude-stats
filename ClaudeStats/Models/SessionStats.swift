import Foundation

/// Everything extracted from a transcript file: a title, message count,
/// activity window, per-model token totals (with cost), and a per-day
/// breakdown for charting.
struct SessionStats: Sendable, Hashable {
    var title: String
    var messageCount: Int
    var firstActivity: Date?
    var lastActivity: Date?
    var models: [ModelUsage]
    var daily: [DaySlice]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { models.reduce(0) { $0 + $1.estimatedCost } }
}
