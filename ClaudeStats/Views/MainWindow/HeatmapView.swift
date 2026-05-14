import SwiftUI

/// GitHub-style yearly heatmap: a 7-row grid of week columns, with cell colour
/// driven by a quartile bucketing over the visible window's non-zero values.
///
/// The ramp uses the app's warm `.stxAccent` at four opacity stops, so it sits
/// inside the instrument-panel chrome instead of borrowing GitHub's green.
struct HeatmapView: View {
    let cells: [HeatmapCell]
    let range: DateInterval
    /// Builds the hover label, e.g. `"5 commits"` or `"12.4k tokens"`. Receives
    /// raw `value`; the view appends the date.
    let valueLabel: (Int) -> String

    private let cellSize: CGFloat = 11
    private let spacing: CGFloat = 2

    private var grid: CalendarGrid { CalendarGrid(spanning: range) }
    private var valuesByDay: [Date: Int] {
        Dictionary(uniqueKeysWithValues: cells.map { ($0.date, $0.value) })
    }
    private var quartiles: [Int] {
        let nonZero = cells.compactMap { $0.value > 0 ? $0.value : nil }.sorted()
        guard !nonZero.isEmpty else { return [] }
        func q(_ p: Double) -> Int {
            let idx = min(max(Int(Double(nonZero.count - 1) * p), 0), nonZero.count - 1)
            return nonZero[idx]
        }
        return [q(0.25), q(0.50), q(0.75)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthLabels
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                gridBody
            }
            legend
        }
    }

    // MARK: - Sub-views

    private var monthLabels: some View {
        let positions = grid.monthLabelPositions()
        let columnStride = cellSize + spacing
        // Width = (weeks * columnStride) - spacing, but pad enough that the
        // last month label has room.
        return ZStack(alignment: .topLeading) {
            ForEach(positions, id: \.weekIndex) { pos in
                Text(pos.label)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .offset(x: CGFloat(pos.weekIndex) * columnStride)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 11)
        .padding(.leading, 22) // align past the weekday label column
    }

    private var weekdayLabels: some View {
        VStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { row in
                let visible = row.isMultiple(of: 2) == false // rows 1, 3, 5
                Text(visible ? grid.weekdaySymbols[row] : " ")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 16, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var gridBody: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<grid.weeks.count, id: \.self) { weekIdx in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { dayIdx in
                        cell(for: grid.weeks[weekIdx][dayIdx])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for date: Date) -> some View {
        if range.contains(date) {
            let value = valuesByDay[date] ?? 0
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(for: value))
                .frame(width: cellSize, height: cellSize)
                .help("\(valueLabel(value)) · \(Self.dateFormatter.string(from: date))")
        } else {
            // Out-of-range padding day (first/last partial week).
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.sora(9)).foregroundStyle(Color.stxMuted)
            ForEach(0..<5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(rampColor(step: step))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More").font(.sora(9)).foregroundStyle(Color.stxMuted)
        }
        .padding(.leading, 22)
    }

    // MARK: - Colour ramp

    private func color(for value: Int) -> Color {
        guard value > 0 else { return rampColor(step: 0) }
        let q = quartiles
        if q.isEmpty { return rampColor(step: 1) }
        if value <= q[0] { return rampColor(step: 1) }
        if value <= q[1] { return rampColor(step: 2) }
        if value <= q[2] { return rampColor(step: 3) }
        return rampColor(step: 4)
    }

    /// 0 = empty cell colour; 1…4 = increasingly saturated accent. We layer
    /// accent over panel so the empty stop is a tinted muted background that
    /// reads as "this day is in range, no activity" — not "no data".
    private func rampColor(step: Int) -> Color {
        switch step {
        case 0: return Color.primary.opacity(0.08)
        case 1: return Color.stxAccent.opacity(0.22)
        case 2: return Color.stxAccent.opacity(0.45)
        case 3: return Color.stxAccent.opacity(0.72)
        default: return Color.stxAccent
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
#Preview("Heatmap — populated") {
    let cal = Calendar.current
    let now = Date.now
    let range = DateInterval(
        start: cal.date(byAdding: .day, value: -364, to: cal.startOfDay(for: now))!,
        end: cal.dateInterval(of: .day, for: now)!.end
    )
    var cells: [HeatmapCell] = []
    var rng = SystemRandomNumberGenerator()
    for offset in 0..<365 {
        let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
        let r = Int.random(in: 0...10, using: &rng)
        let value = r < 4 ? 0 : (r < 7 ? 1 : (r < 9 ? 3 : 8))
        if value > 0 { cells.append(HeatmapCell(date: day, value: value)) }
    }
    return HeatmapView(cells: cells, range: range, valueLabel: { "\($0) commits" })
        .padding()
        .frame(width: 760)
}

#Preview("Heatmap — empty") {
    let cal = Calendar.current
    let range = DateInterval(
        start: cal.date(byAdding: .day, value: -90, to: cal.startOfDay(for: .now))!,
        end: cal.dateInterval(of: .day, for: .now)!.end
    )
    return HeatmapView(cells: [], range: range, valueLabel: { "\($0) commits" })
        .padding()
        .frame(width: 760)
}
#endif
