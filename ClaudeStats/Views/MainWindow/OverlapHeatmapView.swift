import SwiftUI

/// Renders the four-state Overlap heatmap (both / local-only / GitHub-only /
/// neither) using the same week-column skeleton as ``HeatmapView``. The
/// per-cell fill comes from the user-selected ``OverlapPalette``.
struct OverlapHeatmapView: View {
    let stats: OverlapStats
    let range: DateInterval
    let palette: OverlapPalette
    /// Builds the per-cell hover label using local + GitHub values for the
    /// day. The view appends the date.
    let valueLabel: (OverlapStats.DayState) -> String

    /// Pre-formatted tooltip per day. Built off `stats.byDay` + `range`;
    /// keeps `DateFormatter.string` out of the per-cell render path so the
    /// heatmap doesn't get expensive when its container resizes.
    @State private var helpByDay: [Date: String] = [:]

    var body: some View {
        ResponsiveHeatmap(weekCount: HeatmapMetrics.weekCount(for: range)) { cellSize in
            VStack(alignment: .leading, spacing: 6) {
                CalendarGridCanvas(range: range, cellSize: cellSize, help: { helpByDay[$0] ?? "" }) { date, _ in
                    style(for: stats.byDay[date] ?? .neither)
                }
                legend(cellSize: cellSize)
            }
        }
        .onAppear { recomputeHelp() }
        .onChange(of: stats) { _, _ in recomputeHelp() }
        .onChange(of: range) { _, _ in recomputeHelp() }
    }

    private func recomputeHelp() {
        let grid = CalendarGrid(spanning: range)
        var help: [Date: String] = [:]
        help.reserveCapacity(grid.weeks.count * 7)
        let fmt = Self.dateFormatter
        for week in grid.weeks {
            for day in week where range.contains(day) {
                let state = stats.byDay[day] ?? .neither
                help[day] = "\(valueLabel(state)) · \(fmt.string(from: day))"
            }
        }
        helpByDay = help
    }

    private func style(for state: OverlapStats.DayState) -> HeatmapCellStyle {
        HeatmapCellStyle(
            fill: palette.color(for: state),
            border: palette.dashedBorder(for: state) ? Color.stxAccent : nil,
            borderStyle: StrokeStyle(lineWidth: 1, dash: [2, 1.5])
        )
    }

    private func legend(cellSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            ForEach(OverlapStats.DayState.allCases, id: \.self) { state in
                HStack(spacing: 4) {
                    let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                    shape
                        .fill(palette.color(for: state))
                        .frame(width: cellSize, height: cellSize)
                        .overlay {
                            if palette.dashedBorder(for: state) {
                                shape.strokeBorder(Color.stxAccent, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                            }
                        }
                    Text(Self.legendLabel(for: state))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
        }
        .padding(.leading, HeatmapMetrics.weekdayColumnWidth + HeatmapMetrics.weekdayGap)
    }

    private static func legendLabel(for state: OverlapStats.DayState) -> String {
        switch state {
        case .both: "Both"
        case .localOnly: "Local only"
        case .githubOnly: "GitHub only"
        case .neither: "Neither"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

#if DEBUG
#Preview("Overlap — populated") {
    let cal = Calendar.current
    let now = Date.now
    let range = DateInterval(
        start: cal.date(byAdding: .day, value: -180, to: cal.startOfDay(for: now))!,
        end: cal.dateInterval(of: .day, for: now)!.end
    )
    var local: [HeatmapCell] = []
    var github: [HeatmapCell] = []
    var rng = SystemRandomNumberGenerator()
    for offset in 0..<181 {
        let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
        let l = Int.random(in: 0...3, using: &rng)
        let g = Int.random(in: 0...4, using: &rng)
        if l > 0 { local.append(HeatmapCell(date: day, value: l)) }
        if g > 0 { github.append(HeatmapCell(date: day, value: g)) }
    }
    let stats = OverlapStats.compute(local: local, github: github, range: range)
    return VStack(alignment: .leading) {
        ForEach(OverlapPalette.allCases) { palette in
            Text(palette.displayName).font(.sora(11, weight: .semibold))
            OverlapHeatmapView(stats: stats, range: range, palette: palette) { state in
                switch state {
                case .both: "Both"
                case .localOnly: "Local only"
                case .githubOnly: "GitHub only"
                case .neither: "Inactive"
                }
            }
        }
    }
    .padding()
    .frame(width: 760)
}
#endif
