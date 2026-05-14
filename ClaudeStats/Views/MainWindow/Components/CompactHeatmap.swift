import SwiftUI

/// A compact 3-month heatmap. Uses `ResponsiveHeatmap` so it adapts to its
/// container's width — cell size clamps to `HeatmapMetrics.cellSizeMax` (11pt)
/// when the container is wider than the natural heatmap, so the grid sits
/// left-aligned without stretching.
///
/// No legend (the dashboard has limited vertical space and the color ramp is
/// self-evident at this scale).
struct CompactHeatmap: View {
    let cells: [HeatmapCell]
    let range: DateInterval
    /// Tooltip body for a non-empty cell. Receives the raw `value`; the date
    /// is appended automatically.
    var valueLabel: (Int) -> String = { Format.tokens($0) + " tokens" }

    @State private var valuesByDay: [Date: Int] = [:]
    @State private var quartiles: [Int] = []

    var body: some View {
        ResponsiveHeatmap(weekCount: HeatmapMetrics.weekCount(for: range)) { cellSize in
            CalendarGridSkeleton(range: range, cellSize: cellSize) { date, inRange in
                if inRange {
                    let value = valuesByDay[date] ?? 0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: value))
                        .frame(width: cellSize, height: cellSize)
                        .help(value == 0
                              ? Self.dateFormatter.string(from: date)
                              : "\(valueLabel(value)) · \(Self.dateFormatter.string(from: date))")
                } else {
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
            }
        }
        .onAppear { recompute() }
        .onChange(of: cells) { _, _ in recompute() }
    }

    private func recompute() {
        valuesByDay = Dictionary(uniqueKeysWithValues: cells.map { ($0.date, $0.value) })
        let nonZero = cells.compactMap { $0.value > 0 ? $0.value : nil }.sorted()
        guard !nonZero.isEmpty else { quartiles = []; return }
        func q(_ p: Double) -> Int {
            let idx = min(max(Int(Double(nonZero.count - 1) * p), 0), nonZero.count - 1)
            return nonZero[idx]
        }
        quartiles = [q(0.25), q(0.50), q(0.75)]
    }

    private func color(for value: Int) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.08) }
        let q = quartiles
        if q.isEmpty { return Color.stxAccent.opacity(0.22) }
        if value <= q[0] { return Color.stxAccent.opacity(0.22) }
        if value <= q[1] { return Color.stxAccent.opacity(0.45) }
        if value <= q[2] { return Color.stxAccent.opacity(0.72) }
        return Color.stxAccent
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

#if DEBUG
#Preview {
    let cal = Calendar.current
    let now = Date.now
    let range = DateInterval(
        start: cal.date(byAdding: .day, value: -89, to: cal.startOfDay(for: now))!,
        end: cal.dateInterval(of: .day, for: now)!.end
    )
    var cells: [HeatmapCell] = []
    var rng = SystemRandomNumberGenerator()
    for offset in 0..<90 {
        let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
        let r = Int.random(in: 0...10, using: &rng)
        if r > 5 { cells.append(HeatmapCell(date: day, value: r * 1000)) }
    }
    return HStack(spacing: 16) {
        CompactHeatmap(cells: cells, range: range)
            .padding(14)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10))
        CompactHeatmap(cells: cells, range: range, valueLabel: { "\($0) contributions" })
            .padding(14)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10))
    }
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
