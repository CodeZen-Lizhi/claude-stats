import Foundation

/// Per-model token totals plus the cost they imply under a ``ModelPricing``
/// table. Cost is baked in at construction so views never need the pricing
/// table in scope.
struct ModelUsage: Sendable, Hashable, Identifiable {
    let model: String
    let messageCount: Int
    let usage: TokenUsage
    let estimatedCost: Double

    var id: String { model }

    init(model: String, messageCount: Int, usage: TokenUsage, pricing: ModelPricing) {
        self.model = model
        self.messageCount = messageCount
        self.usage = usage
        self.estimatedCost = pricing.cost(model: model, usage: usage)
    }

    init(model: String, messageCount: Int, usage: TokenUsage, estimatedCost: Double) {
        self.model = model
        self.messageCount = messageCount
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

extension Array where Element == ModelUsage {
    /// Merge per-model entries by model id, preserving already-computed cost.
    /// Cost may be request-sensitive (for example long-context rates), so it
    /// must be summed rather than recomputed from aggregate tokens.
    func merged(pricing _: ModelPricing) -> [ModelUsage] {
        var byModel: [String: (count: Int, usage: TokenUsage, cost: Double)] = [:]
        for entry in self {
            var acc = byModel[entry.model] ?? (0, .zero, 0)
            acc.count += entry.messageCount
            acc.usage += entry.usage
            acc.cost += entry.estimatedCost
            byModel[entry.model] = acc
        }
        return byModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, estimatedCost: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
    }
}
