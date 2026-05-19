import SwiftUI
import Charts

struct UsageTrendPanel: View {
    let series: TrendSeries
    let rangeID: String
    @Binding var chartStyle: TrendChartStyle
    @Binding var scaleMode: TrendScaleMode
    @Binding var stackByType: Bool
    let displayName: (String) -> String

    private var isHourly: Bool { series.granularity == .hour }
    private var effectiveStyle: TrendChartStyle { isHourly ? .line : chartStyle }
    private var useLog: Bool { !isHourly && effectiveStyle == .line && !stackByType && scaleMode == .log }
    private var snapshot: UsageTrendChartSnapshot {
        UsageTrendChartSnapshot(
            series: series,
            rangeID: rangeID,
            style: effectiveStyle,
            useLog: useLog,
            stackByType: stackByType,
            displayName: displayName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(caption)
                .font(.sora(10))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)

            UsageTrendChartView(
                snapshot: snapshot,
                chartHeight: 220,
                emptyMessage: emptyMessage
            ) {
                legend(snapshot.legendEntries)
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

    private var emptyMessage: String {
        isHourly ? "No usage today yet." : "No usage for this period."
    }

    private func legend(_ entries: [UsageTrendLegendEntry]) -> some View {
        LazyVGrid(
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
                rangeID: StatsPeriod.last30Days.rawValue,
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
