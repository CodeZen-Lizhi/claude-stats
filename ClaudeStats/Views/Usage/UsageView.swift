import SwiftUI
import Charts

struct UsageView: View {
    /// Frozen chart settings for an exported panel — the share window's choices,
    /// since the export view can't carry the interactive view model's state.
    struct ExportConfig: Hashable {
        var period: PeriodSelection
        var chartStyle: TrendChartStyle = .line
        var useLog: Bool = false
    }

    /// `interactive` is the normal in-panel view; `export` drives the summary
    /// and chart settings from a fixed ``ExportConfig`` and renders a static
    /// (non-scrolling) body so it can be captured by `ImageRenderer`.
    enum Mode: Hashable { case interactive, export(ExportConfig) }

    @Environment(AppEnvironment.self) private var env
    @State private var vm = UsageViewModel()
    var mode: Mode = .interactive

    private var exportConfig: ExportConfig? {
        if case .export(let config) = mode { return config }
        return nil
    }

    var body: some View {
        @Bindable var vm = vm
        let provider = env.preferences.selectedProvider
        let summary = exportConfig.map { env.store.summary(for: $0.period, provider: provider) } ?? vm.summary(from: env.store, provider: provider)
        let series = summary.trendSeries()
        let isHourly = series.granularity == .hour
        let style: TrendChartStyle = isHourly ? .line : (exportConfig?.chartStyle ?? vm.chartStyle)
        let useLog = style == .line && (exportConfig?.useLog ?? (vm.scaleMode == .log))
        let interactive = exportConfig == nil

        let content = VStack(alignment: .leading, spacing: 16) {
            if interactive {
                HStack(spacing: 0) {
                    ForEach(Array(StatsPeriod.allCases.enumerated()), id: \.element) { idx, p in
                        if idx > 0 { Spacer(minLength: 8) }
                        PeriodTab(period: p, isSelected: vm.period == p) { vm.period = p }
                    }
                }
            }

            statGrid(summary)
            breakdownPanel(summary, series: series, isHourly: isHourly, style: style, useLog: useLog,
                           interactive: interactive, exportPeriod: exportConfig?.period)
            modelBreakdown(summary, series: series)
        }
        .padding(14)

        if interactive {
            FadingScrollView { content }
        } else {
            content
        }
    }

    private func periodReadout(_ selection: PeriodSelection) -> some View {
        BracketBox(spacing: 7) {
            Text("PERIOD:")
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(selection.label())
                .font(.sora(11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Stat readouts

    private func statGrid(_ s: UsageSummary) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell("Tokens", Format.tokens(s.totalTokens))
                statCell("Est. cost", Format.cost(s.totalCost))
            }
            GridRow {
                statCell("Sessions", "\(s.sessionCount)")
                statCell("Messages", Format.tokens(s.messageCount))
            }
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        BracketBox(spacing: 7) {
            Text(title.uppercased() + ":")
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .layoutPriority(-1)
            Text(value)
                .font(.sora(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
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
    private func breakdownPanel(_ s: UsageSummary, series: TrendSeries, isHourly: Bool, style: TrendChartStyle, useLog: Bool, interactive: Bool, exportPeriod: PeriodSelection?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("BREAKDOWN")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
                if interactive && !series.buckets.isEmpty {
                    trendControls(style: style, showStyleToggle: !isHourly)
                }
            }
            Text(captionText(isHourly: isHourly, style: style, useLog: useLog, annotate: !interactive))
                .font(.sora(9))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if series.buckets.isEmpty {
                Text(isHourly ? "No usage today yet." : "No usage for this period.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                legend(series)
                StxRule()
                chart(series: series, isHourly: isHourly, style: style, useLog: useLog)
            }
            if let exportPeriod {
                StxRule()
                periodReadout(exportPeriod)
            }
        }
        .stxPanel(12)
    }

    private func captionText(isHourly: Bool, style: TrendChartStyle, useLog: Bool, annotate: Bool) -> String {
        var parts = [isHourly ? "TOKENS TODAY · HOURLY" : "TOKENS PER DAY"]
        if annotate {
            parts.append(style == .bar ? "BARS" : "LINE")
            if useLog { parts.append("LN SCALE") }
        }
        return parts.joined(separator: " · ")
    }

    private func legend(_ series: TrendSeries) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 4) {
            ForEach(Array(series.models.enumerated()), id: \.element) { idx, model in
                BracketBox(spacing: 6) {
                    Rectangle().fill(ModelPalette.color(at: idx)).frame(width: 7, height: 7)
                    Text(model)
                        .font(.sora(9))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func chart(series: TrendSeries, isHourly: Bool, style: TrendChartStyle, useLog: Bool) -> some View {
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
                .lineStyle(StrokeStyle(lineWidth: 2))
            case .bar:
                BarMark(
                    x: .value("Day", p.date, unit: .day),
                    y: .value("Tokens", p.value)
                )
                .foregroundStyle(by: .value("Model", p.model))
                .cornerRadius(0)
            }
        }
        .chartForegroundStyleScale(mapping: { (model: String) in
            ModelPalette.color(at: series.models.firstIndex(of: model) ?? 0)
        })
        .chartYScale(domain: 0...(maxY * 1.05))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Format.tokens(Int(useLog ? expm1(v) : v)))
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
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.hour())
                                .font(.sora(8))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            } else {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.stxStroke)
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.month(.abbreviated).day())
                                .font(.sora(8))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 150)
    }

    @ViewBuilder
    private func trendControls(style: TrendChartStyle, showStyleToggle: Bool) -> some View {
        HStack(spacing: 6) {
            if style == .line {
                controlButton(
                    systemName: "function",
                    active: vm.scaleMode == .log,
                    help: "Compress large gaps between models (ln scale)"
                ) {
                    vm.scaleMode = vm.scaleMode == .linear ? .log : .linear
                }
            }
            if showStyleToggle {
                controlButton(
                    systemName: vm.chartStyle == .line ? "chart.xyaxis.line" : "chart.bar.xaxis",
                    active: false,
                    help: vm.chartStyle == .line ? "Switch to bar chart" : "Switch to line chart"
                ) {
                    vm.chartStyle = vm.chartStyle == .line ? .bar : .line
                }
            }
        }
    }

    private struct PeriodTab: View {
        let period: StatsPeriod
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Text(period.displayName.uppercased())
                        .font(.sora(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    Rectangle()
                        .fill(Color.stxAccent)
                        .frame(height: 1.5)
                        .scaleEffect(x: isSelected ? 1 : 0, anchor: .leading)
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.22), value: isSelected)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var textColor: Color {
            if isSelected { return .primary }
            return hovering ? .primary : Color.primary.opacity(0.40)
        }
    }

    private func controlButton(systemName: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BracketBox(spacing: 3) {
                Image(systemName: systemName).font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.stxAccent : Color.stxMuted)
        .help(help)
    }

    // MARK: Per-model breakdown

    @ViewBuilder
    private func modelBreakdown(_ s: UsageSummary, series: TrendSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MODEL")
                .font(.sora(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.stxMuted)
            if s.models.isEmpty {
                Text("No usage recorded for this period.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
            } else {
                let maxTokens = max(1, s.models.map(\.usage.total).max() ?? 1)
                ForEach(Array(s.models.enumerated()), id: \.element.id) { idx, model in
                    let color = ModelPalette.color(at: series.models.firstIndex(of: model.model) ?? idx)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Rectangle().fill(color).frame(width: 7, height: 7)
                            Text(model.model)
                                .font(.sora(10))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Format.tokens(model.usage.total))
                                .font(.sora(10).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text(Format.cost(model.estimatedCost))
                                .font(.sora(10).monospacedDigit())
                                .foregroundStyle(Color.stxMuted)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.primary.opacity(0.09))
                                Rectangle()
                                    .fill(color)
                                    .frame(width: max(2, geo.size.width * CGFloat(model.usage.total) / CGFloat(maxTokens)))
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Light") {
    UsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    UsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}
#endif
