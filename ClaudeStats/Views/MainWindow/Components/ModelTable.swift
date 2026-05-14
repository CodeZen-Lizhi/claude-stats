import SwiftUI

/// Compact per-model token bars, sorted by total token usage descending.
/// Rendered inside the Dashboard's "Models" tab. Inspired by the BY MODEL
/// breakdown in `UsageView`, but slimmer (no cache-read stripes, no headers)
/// because the dashboard cards already provide context.
struct ModelTable: View {
    let models: [ModelUsage]
    var includeCacheInTotals: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if models.isEmpty {
                Text("No model data in this range.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                let maxTokens = max(1, models.first?.usage.total(includingCacheRead: includeCacheInTotals) ?? 1)
                ForEach(Array(models.enumerated()), id: \.element.id) { (index, usage) in
                    row(usage, index: index, maxTokens: maxTokens)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func row(_ usage: ModelUsage, index: Int, maxTokens: Int) -> some View {
        let total = usage.usage.total(includingCacheRead: includeCacheInTotals)
        let ratio = max(0, min(1, Double(total) / Double(maxTokens)))
        let swatch = Color.stxRamp[index % Color.stxRamp.count]

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(swatch)
                    .frame(width: 10, height: 10)
                Text(usage.model)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(Format.tokens(total))
                    .font(.sora(11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(Format.cost(usage.estimatedCost))
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 56, alignment: .trailing)
            }
            // Two stacked rounded rectangles. The foreground bar fills the
            // full row width and then horizontally scales to `ratio` from the
            // leading edge — avoids a per-row `GeometryReader` that would
            // re-measure on every container resize.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(swatch.opacity(0.85))
                    .scaleEffect(x: max(0.002, ratio), y: 1, anchor: .leading)
            }
            .frame(height: 6)
        }
    }
}

#if DEBUG
#Preview {
    let pricing = ModelPricing.fallback
    let mu: (String, Int, Int) -> ModelUsage = { name, msgs, total in
        ModelUsage(
            model: name,
            messageCount: msgs,
            usage: TokenUsage(inputTokens: total / 2, outputTokens: total / 4, cacheReadTokens: total / 4, cacheCreation5mTokens: 0, cacheCreation1hTokens: 0),
            pricing: pricing
        )
    }
    return ModelTable(models: [
        mu("claude-opus-4-7", 410, 90_000_000),
        mu("claude-sonnet-4-6", 220, 18_500_000),
        mu("claude-haiku-4-5", 110, 5_400_000),
        mu("claude-3.5-sonnet", 80, 950_000),
    ])
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
