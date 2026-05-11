import SwiftUI
import Charts

struct UsageView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = UsageViewModel()

    var body: some View {
        @Bindable var vm = vm
        let summary = vm.summary(from: env.store)
        FadingScrollView {
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

    private struct TrendPoint: Identifiable {
        let model: String
        let date: Date
        let value: Double
        var id: String { "\(model)|\(date.timeIntervalSinceReferenceDate)" }
    }

    /// Per-model points for the trend chart. In line mode the per-bucket token
    /// counts are smoothed (and optionally `log1p`-compressed); in bar mode
    /// they're the raw counts with empty buckets dropped, so each day renders
    /// one stacked bar of segments.
    private func trendPoints(_ series: TrendSeries, style: TrendChartStyle, useLog: Bool) -> [TrendPoint] {
        switch style {
        case .bar:
            return series.models.flatMap { model in
                series.buckets(for: model)
                    .filter { $0.tokens > 0 }
                    .map { TrendPoint(model: model, date: $0.start, value: Double($0.tokens)) }
            }
        case .line:
            let count = series.buckets(for: series.models.first ?? "").count
            let window = Smoothing.adaptiveWindow(count: count, granularity: series.granularity)
            return series.models.flatMap { model -> [TrendPoint] in
                let buckets = series.buckets(for: model)
                var values = Smoothing.movingAverage(buckets.map { Double($0.tokens) }, window: window)
                if useLog { values = values.map { log1p($0) } }
                return zip(buckets, values).map { TrendPoint(model: model, date: $0.start, value: $1) }
            }
        }
    }

    @ViewBuilder
    private func trendChart(_ s: UsageSummary) -> some View {
        let series = s.trendSeries()
        let isHourly = series.granularity == .hour
        let style: TrendChartStyle = isHourly ? .line : vm.chartStyle
        let useLog = style == .line && vm.scaleMode == .log
        VStack(alignment: .leading, spacing: 6) {
            Text(isHourly ? "Tokens today (hourly)" : "Tokens per day")
                .font(.caption).foregroundStyle(.secondary)
            if series.buckets.isEmpty {
                Text(isHourly ? "No usage today yet." : "No usage for this period.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let points = trendPoints(series, style: style, useLog: useLog)
                let maxY = max(1, points.map(\.value).max() ?? 1)
                Chart(points) { p in
                    switch style {
                    case .line:
                        LineMark(
                            x: .value("Time", p.date, unit: isHourly ? .hour : .day),
                            y: .value("Tokens", p.value)
                        )
                        .foregroundStyle(by: .value("Model", p.model))
                        .interpolationMethod(.catmullRom)
                    case .bar:
                        BarMark(
                            x: .value("Day", p.date, unit: .day),
                            y: .value("Tokens", p.value)
                        )
                        .foregroundStyle(by: .value("Model", p.model))
                    }
                }
                .chartForegroundStyleScale(mapping: { (model: String) in ModelPalette.color(for: model) })
                .chartYScale(domain: 0...(maxY * 1.05))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(Format.tokens(Int(useLog ? expm1(v) : v)))
                            }
                        }
                    }
                }
                .chartXAxis {
                    if isHourly {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    } else {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 6)
                .frame(height: 150)

                trendControls(style: style, showStyleToggle: !isHourly)
            }
        }
    }

    @ViewBuilder
    private func trendControls(style: TrendChartStyle, showStyleToggle: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()
            if style == .line {
                Button {
                    vm.scaleMode = vm.scaleMode == .linear ? .log : .linear
                } label: {
                    Image(systemName: "function")
                }
                .foregroundStyle(vm.scaleMode == .log ? Color.accentColor : Color.secondary)
                .help("Compress large gaps between models (ln scale)")
            }
            if showStyleToggle {
                Button {
                    vm.chartStyle = vm.chartStyle == .line ? .bar : .line
                } label: {
                    Image(systemName: vm.chartStyle == .line ? "chart.xyaxis.line" : "chart.bar.xaxis")
                }
                .foregroundStyle(Color.secondary)
                .help(vm.chartStyle == .line ? "Switch to bar chart" : "Switch to line chart")
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
        .font(.callout)
        .padding(.top, 2)
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
                            Circle()
                                .fill(ModelPalette.color(for: model.model))
                                .frame(width: 8, height: 8)
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
                            .tint(ModelPalette.color(for: model.model))
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
