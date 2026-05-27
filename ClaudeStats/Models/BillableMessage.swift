import Foundation

/// A single assistant turn's billable contribution, kept around so cross-session
/// aggregation can dedup messages that appear in more than one transcript file.
///
/// When a provider records one assistant turn in more than one transcript file,
/// aggregating tokens / cost across sessions can count the same turn twice.
///
/// The fix: every assistant message we count remembers its provider-stable
/// `(message.id, requestId)` hash. ``UsageSummary/make(period:sessions:...)``
/// iterates ``BillableMessage`` lists across sessions and skips hashes it has
/// already seen.
///
/// `hash` is optional because not every provider supplies request IDs. A
/// `nil`-hash message is never deduped (every instance is counted), which is
/// the safe default for providers without the
/// subagent fan-out pattern.
struct BillableMessage: Sendable, Hashable {
    /// Stable cross-file identity: `"\(message.id):\(requestId)"` when both
    /// are present. `nil` disables cross-session dedup for this message.
    let hash: String?
    let model: String
    let usage: TokenUsage
    let cost: CostEstimate
    /// Used to rebuild the per-hour timeline after dedup. `nil` messages still
    /// contribute to totals but never appear in the timeline.
    let timestamp: Date?
}

extension BillableMessage: Codable {}
