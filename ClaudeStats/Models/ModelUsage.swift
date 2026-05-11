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
}

extension Array where Element == ModelUsage {
    /// Merge per-model entries by model id, re-summing usage. `pricing`
    /// recomputes cost; since cost is linear in tokens the result equals
    /// summing the inputs' costs.
    func merged(pricing: ModelPricing) -> [ModelUsage] {
        var byModel: [String: (count: Int, usage: TokenUsage)] = [:]
        for entry in self {
            var acc = byModel[entry.model] ?? (0, .zero)
            acc.count += entry.messageCount
            acc.usage += entry.usage
            byModel[entry.model] = acc
        }
        return byModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, pricing: pricing) }
            .sorted { $0.usage.total > $1.usage.total }
    }
}
