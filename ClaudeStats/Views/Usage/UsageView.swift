import SwiftUI
import Charts

struct UsageView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = UsageViewModel()

    var body: some View {
        @Bindable var vm = vm
        let summary = vm.summary(from: env.store)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $vm.period) {
                    ForEach(StatsPeriod.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                statCards(summary)
                trendChart(summary)
                modelBreakdown(summary)
            }
            .padding(12)
        }
    }

    // MARK: Stat cards

    private func statCards(_ s: UsageSummary) -> some View {
        HStack(spacing: 8) {
            statCard("Tokens", Format.tokens(s.totalTokens), "number")
            statCard("Est. cost", Format.cost(s.totalCost), "dollarsign.circle")
            statCard("Sessions", "\(s.sessionCount)", "bubble.left.and.bubble.right")
        }
    }

    private func statCard(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Trend chart

    @ViewBuilder
    private func trendChart(_ s: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tokens per day").font(.caption).foregroundStyle(.secondary)
            if s.daily.isEmpty {
                Text("No daily data for this period.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(s.daily) { slice in
                    BarMark(
                        x: .value("Day", slice.day, unit: .day),
                        y: .value("Tokens", slice.tokens)
                    )
                    .foregroundStyle(ProviderKind.claude.accentColor)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let tokens = value.as(Int.self) { Text(Format.tokens(tokens)) }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: Per-model breakdown

    @ViewBuilder
    private func modelBreakdown(_ s: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By model").font(.caption).foregroundStyle(.secondary)
            if s.models.isEmpty {
                Text("No usage recorded for this period.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                let maxTokens = max(1, s.models.map(\.usage.total).max() ?? 1)
                ForEach(s.models) { model in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(model.model).font(.caption).lineLimit(1)
                            Spacer()
                            Text(Format.tokens(model.usage.total))
                                .font(.caption.monospacedDigit())
                            Text(Format.cost(model.estimatedCost))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(model.usage.total), total: Double(maxTokens))
                            .progressViewStyle(.linear)
                            .tint(ProviderKind.claude.accentColor)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    UsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 460)
}
#endif
