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
    /// activity analysis to overlap against coding-surface and CLI-host time.
    var activityIntervals: [DateInterval] = []
    /// Per-assistant-message billable units, one entry per turn we counted in
    /// ``models`` / ``timeline``. Carried so cross-session aggregation in
    /// ``UsageSummary/make(period:sessions:pricing:now:calendar:)`` can dedup
    /// the subagent-turn duplication described in ``BillableMessage``.
    /// Empty when the provider doesn't populate it (e.g. Codex transcripts);
    /// the aggregator falls back to ``models`` in that case.
    var billableMessages: [BillableMessage] = []
    /// Provider parser state at the end of the transcript, used to continue
    /// parsing appended bytes without re-reading old lines.
    var lastModel: String?

    init(
        title: String,
        messageCount: Int,
        firstActivity: Date?,
        lastActivity: Date?,
        models: [ModelUsage],
        timeline: [ModelBucket],
        activityIntervals: [DateInterval] = [],
        billableMessages: [BillableMessage] = [],
        lastModel: String? = nil
    ) {
        self.title = title
        self.messageCount = messageCount
        self.firstActivity = firstActivity
        self.lastActivity = lastActivity
        self.models = models
        self.timeline = timeline
        self.activityIntervals = activityIntervals
        self.billableMessages = billableMessages
        self.lastModel = lastModel
    }

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { totalCost(for: .standardAPI) }

    func totalTokens(includingCacheRead: Bool) -> Int {
        totalUsage.total(includingCacheRead: includingCacheRead)
    }

    func totalCost(for mode: CostEstimationMode) -> Double {
        models.reduce(0) { $0 + $1.estimatedCost(for: mode) }
    }
}
