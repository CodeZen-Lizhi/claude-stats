import SwiftUI

struct UsageModelBreakdown: View {
    let models: [ModelUsage]
    let includeCacheInTokens: Bool
    let costEstimationMode: CostEstimationMode
    let displayName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BY MODEL")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("Tokens · Cost · Share")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if models.isEmpty {
                Text("No model data in this range.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { _, model in
                        UsageModelRow(
                            model: model,
                            color: color(for: model),
                            totalTokens: totalTokens(for: model),
                            maxTokens: maxTokens,
                            allTokens: allTokens,
                            includeCacheInTokens: includeCacheInTokens,
                            costEstimationMode: costEstimationMode,
                            displayName: displayName(model.model)
                        )
                        if model.id != models.last?.id {
                            StxRule()
                        }
                    }
                }
            }
        }
        .mainUsagePanel(padding: 16)
    }

    private var allTokens: Int {
        max(1, models.reduce(0) { $0 + totalTokens(for: $1) })
    }

    private var maxTokens: Int {
        max(1, models.map(totalTokens(for:)).max() ?? 1)
    }

    private func totalTokens(for model: ModelUsage) -> Int {
        model.usage.total(includingCacheRead: includeCacheInTokens)
    }

    private func color(for model: ModelUsage) -> Color {
        ModelPalette.color(for: model.model)
    }
}

private struct UsageModelRow: View {
    let model: ModelUsage
    let color: Color
    let totalTokens: Int
    let maxTokens: Int
    let allTokens: Int
    let includeCacheInTokens: Bool
    let costEstimationMode: CostEstimationMode
    let displayName: String

    private var share: Double {
        Double(totalTokens) / Double(max(1, allTokens))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(displayName)
                    .font(.sora(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(Format.tokens(totalTokens))
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: Format.tokens(totalTokens))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 72, alignment: .trailing)
                Text(Format.cost(model.estimatedCost(for: costEstimationMode)))
                    .font(.sora(12).monospacedDigit())
                    .stxNumericValueTransition(value: Format.cost(model.estimatedCost(for: costEstimationMode)))
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 70, alignment: .trailing)
                Text(Format.percent(share))
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: Format.percent(share))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let solid = max(0, model.usage.total - model.usage.cacheReadTokens)
                let solidWidth = totalWidth * CGFloat(solid) / CGFloat(maxTokens)
                let cachedWidth = includeCacheInTokens
                    ? totalWidth * CGFloat(model.usage.cacheReadTokens) / CGFloat(maxTokens)
                    : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        if solidWidth > 0 {
                            Rectangle()
                                .fill(color)
                                .frame(width: solidWidth)
                        }
                        if cachedWidth > 0 {
                            ZStack {
                                Rectangle().fill(color.opacity(0.68))
                                DiagonalStripes(spacing: 4)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            }
                            .frame(width: cachedWidth)
                            .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 10)
    }
}

struct UsageTokenCompositionPanel: View {
    let usage: TokenUsage
    let includeCacheInTokens: Bool
    let cacheHitRate: Double?

    private var parts: [Part] {
        [
            Part(id: "output", label: "Output", value: usage.outputTokens, color: Color.stxRamp[0]),
            Part(id: "input", label: "Input", value: usage.inputTokens, color: Color.stxRamp[1]),
            Part(id: "cache-write", label: "Cache write", value: usage.cacheCreationTotalTokens, color: Color.stxRamp[2]),
            Part(id: "cache-read", label: "Cache read", value: usage.cacheReadTokens, color: Color.stxRamp[3]),
        ]
    }

    private var compositionTotal: Int {
        max(1, parts.reduce(0) { $0 + $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMPOSITION")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(cacheHitRate.map(Format.percent) ?? "--")
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: cacheHitRate.map(Format.percent) ?? "--")
                    .foregroundStyle(.primary)
                    .help("Cache hit rate")
            }

            compositionBar

            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(part.color)
                            .frame(width: 9, height: 9)
                        Text(part.label)
                            .font(.sora(11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.tokens(part.value))
                            .font(.sora(11).monospacedDigit())
                            .stxNumericValueTransition(value: Format.tokens(part.value))
                            .foregroundStyle(Color.stxMuted)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }

            StxRule()

            VStack(alignment: .leading, spacing: 5) {
                Text(includeCacheInTokens ? "Cache reads are included in totals." : "Cache reads are excluded from totals.")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Cache write tokens are always counted because they represent newly primed context.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .mainUsagePanel(padding: 16)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    let width = proxy.size.width * CGFloat(part.value) / CGFloat(compositionTotal)
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(part.value > 0 ? CGFloat(2) : 0, width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 8)
    }

    private struct Part: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
    }
}

#if DEBUG
#Preview {
    UsageTokenCompositionPanel(
        usage: TokenUsage(inputTokens: 120_000, outputTokens: 82_000, cacheReadTokens: 800_000, cacheCreation5mTokens: 12_000, cacheCreation1hTokens: 44_000),
        includeCacheInTokens: true,
        cacheHitRate: 0.88
    )
    .padding(24)
    .frame(width: 360)
    .background(Color.stxBackground)
}
#endif
