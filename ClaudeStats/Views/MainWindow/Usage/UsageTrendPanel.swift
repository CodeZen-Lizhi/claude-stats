import SwiftUI
import Charts

struct UsageTrendPanel: View {
    let series: TrendSeries
    @Binding var chartStyle: TrendChartStyle
    @Binding var scaleMode: TrendScaleMode
    @Binding var stackByType: Bool
    let displayName: (String) -> String

    private var isHourly: Bool { series.granularity == .hour }
    private var effectiveStyle: TrendChartStyle { isHourly ? .line : chartStyle }
    private var useLog: Bool { !isHourly && effectiveStyle == .line && !stackByType && scaleMode == .log }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(caption)
                .font(.sora(10))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)

            if series.buckets.isEmpty || series.isEmpty {
                emptyState
            } else {
                legend
                StxRule()
                chart
            }
        }
        .mainUsagePanel(padding: 16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("TOKEN TREND")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            Spacer()
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if !isHourly && effectiveStyle == .line && !stackByType {
                UsageIconButton(
                    systemName: "function",
                    active: scaleMode == .log,
                    help: "Compress large gaps between models (ln scale)"
                ) {
                    scaleMode = scaleMode == .linear ? .log : .linear
                }
            }

            UsageIconButton(
                systemName: "square.stack.3d.up.fill",
                active: stackByType,
                help: stackByType
                    ? "Show one series per model"
                    : "Stack by token type"
            ) {
                stackByType.toggle()
            }

            if !isHourly {
                UsageIconButton(
                    systemName: chartStyle == .line ? "chart.xyaxis.line" : "chart.bar.xaxis",
                    active: false,
                    help: chartStyle == .line ? "Switch to bar chart" : "Switch to line chart"
                ) {
                    chartStyle = chartStyle == .line ? .bar : .line
                }
            }
        }
    }

    private var caption: String {
        var parts = [isHourly ? "TOKENS TODAY · HOURLY" : "TOKENS PER DAY"]
        parts.append(effectiveStyle == .bar ? "BARS" : "LINE")
        if stackByType { parts.append("STACKED BY TYPE") }
        if useLog { parts.append("LN SCALE") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        Text(isHourly ? "No usage today yet." : "No usage for this period.")
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private var legend: some View {
        let entries = legendEntries
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(entries) { entry in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(entry.color)
                        .frame(width: 9, height: 9)
                    Text(entry.label)
                        .font(.sora(10))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let points = trendPoints()
        let maxY = chartMaxY(points)
        let base = Chart(points) { point in
            switch effectiveStyle {
            case .line:
                if stackByType {
                    AreaMark(
                        x: .value("Time", point.date, unit: isHourly ? .hour : .day),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(by: .value("Type", point.series))
                    .interpolationMethod(.catmullRom)
                } else {
                    LineMark(
                        x: .value("Time", point.date, unit: isHourly ? .hour : .day),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(by: .value("Model", point.series))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            case .bar:
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Tokens", point.value)
                )
                .foregroundStyle(by: .value(stackByType ? "Type" : "Model", point.series))
                .cornerRadius(1)
            }
        }
        .chartYScale(domain: 0...(maxY * 1.05))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(Format.tokens(Int(useLog ? expm1(raw) : raw)))
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXAxis {
            if isHourly {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine().foregroundStyle(Color.stxStroke)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour())
                                .font(.sora(8))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            } else {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.stxStroke)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.sora(8))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 220)

        if stackByType {
            base.chartForegroundStyleScale(
                domain: Self.tokenTypeKeys.map(\.label),
                range: Self.tokenTypeKeys.map(\.color)
            )
        } else {
            base.chartForegroundStyleScale(mapping: { (key: String) in
                ModelPalette.color(at: series.models.firstIndex(of: key) ?? 0)
            })
        }
    }

    private var legendEntries: [UsageLegendEntry] {
        if stackByType {
            return Self.tokenTypeKeys.map { UsageLegendEntry(id: $0.label, label: $0.label, color: $0.color) }
        }
        return series.models.enumerated().map { index, model in
            UsageLegendEntry(id: model, label: displayName(model), color: ModelPalette.color(at: index))
        }
    }

    private func trendPoints() -> [UsageTrendPoint] {
        if stackByType {
            var byStart: [Date: TokenUsage] = [:]
            for bucket in series.buckets {
                byStart[bucket.start, default: .zero] += bucket.usage
            }
            let starts = byStart.keys.sorted()
            return Self.tokenTypeKeys.flatMap { key in
                starts.compactMap { date -> UsageTrendPoint? in
                    let value = Self.tokenTypeValue(byStart[date] ?? .zero, label: key.label)
                    if effectiveStyle == .bar && value == 0 { return nil }
                    return UsageTrendPoint(series: key.label, date: date, value: Double(value))
                }
            }
        }

        switch effectiveStyle {
        case .bar:
            return series.models.flatMap { model in
                series.buckets(for: model)
                    .filter { $0.tokens > 0 }
                    .map { UsageTrendPoint(series: model, date: $0.start, value: Double($0.tokens)) }
            }
        case .line:
            let count = series.buckets(for: series.models.first ?? "").count
            let window = Smoothing.adaptiveWindow(count: count, granularity: series.granularity)
            return series.models.flatMap { model in
                let buckets = series.buckets(for: model)
                var values = Smoothing.movingAverage(buckets.map { Double($0.tokens) }, window: window)
                if useLog { values = values.map { log1p($0) } }
                return zip(buckets, values).map { UsageTrendPoint(series: model, date: $0.start, value: $1) }
            }
        }
    }

    private func chartMaxY(_ points: [UsageTrendPoint]) -> Double {
        if effectiveStyle == .line && stackByType {
            let sums = Dictionary(grouping: points, by: \.date).mapValues { rows in
                rows.reduce(0) { $0 + $1.value }
            }
            return max(1, sums.values.max() ?? 1)
        }
        return max(1, points.map(\.value).max() ?? 1)
    }

    private static let tokenTypeKeys: [(label: String, color: Color)] = [
        ("Output", Color.stxRamp[0]),
        ("Input", Color.stxRamp[1]),
        ("Cache Write", Color.stxRamp[2]),
        ("Cache Read", Color.stxRamp[3]),
    ]

    private static func tokenTypeValue(_ usage: TokenUsage, label: String) -> Int {
        switch label {
        case "Output": usage.outputTokens
        case "Input": usage.inputTokens
        case "Cache Write": usage.cacheCreationTotalTokens
        case "Cache Read": usage.cacheReadTokens
        default: 0
        }
    }
}

private struct UsageTrendPoint: Identifiable {
    let series: String
    let date: Date
    let value: Double

    var id: String { "\(series)|\(date.timeIntervalSinceReferenceDate)" }
}

private struct UsageLegendEntry: Identifiable {
    let id: String
    let label: String
    let color: Color
}

private struct UsageIconButton: View {
    let systemName: String
    let active: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.stxAccent : (hovering ? .primary : Color.stxMuted))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.stxAccent.opacity(0.12) : (hovering ? Color.primary.opacity(0.08) : .clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State private var style: TrendChartStyle = .line
        @State private var scale: TrendScaleMode = .linear
        @State private var stacked = false

        var body: some View {
            UsageTrendPanel(
                series: UsageSummary.empty(period: .last30Days).trendSeries(),
                chartStyle: $style,
                scaleMode: $scale,
                stackByType: $stacked,
                displayName: { $0 }
            )
            .padding(24)
            .frame(width: 760)
            .background(Color.stxBackground)
        }
    }

    return Wrap()
}
#endif
