import Foundation

/// Everything extracted from a transcript file: a title, message count,
/// activity window, per-model token totals (with cost), and an hourly
/// per-model timeline for charting.
struct SessionStats: Sendable, Hashable {
    var title: String
    var messageCount: Int
    var firstActivity: Date?
    var lastActivity: Date?
    var models: [ModelUsage]
    /// Hourly buckets, one per `(model, hour)` with recorded usage.
    var timeline: [ModelBucket]
    /// Coalesced runs of message activity ("bursts") — adjacent messages
    /// within a gap threshold collapse into one interval. Used by the AI
    /// activity analysis to overlap against editor-focus time.
    var activityIntervals: [DateInterval] = []

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { models.reduce(0) { $0 + $1.estimatedCost } }
}
