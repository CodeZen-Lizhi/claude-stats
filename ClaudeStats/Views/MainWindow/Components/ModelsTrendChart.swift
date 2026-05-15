import SwiftUI

/// Stacked daily token chart for the Dashboard's "Models" tab. One column per
/// day; each column is a stack of per-model segments, busiest model at the
/// base. Within a model's segment, the `cacheRead` portion is rendered with
/// the same colour as the solid portion plus a light diagonal stripe overlay
/// — matching the menu-bar popover's "By model" bars in ``UsageView``.
///
/// The chart is hand-rolled (instead of using `Charts.BarMark`) because
/// `BarMark` can't carry an arbitrary `Shape` overlay per segment.
/// `ModelTable` next to the chart doubles as the legend.
struct ModelsTrendChart: View {
    let series: TrendSeries
    var includeCacheInTotals: Bool = false
    /// Resolves a canonical model id (e.g. `claude-opus-4-7`) to its display
    /// name. Passed in so the chart stays provider-agnostic.
    let displayName: (String) -> String

    private static let chartHeight: CGFloat = 180
    private static let yAxisWidth: CGFloat = 44
    private static let yTickCount: Int = 4   // 4 intervals → 5 labels incl. zero
    private static let targetXLabelCount: Int = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if days.isEmpty {
                placeholder
            } else {
                chart
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    // MARK: - Derived data

    /// Ordered list of days with at least one non-zero model bucket, plus the
    /// per-model usage for that day (kept in the chart's stacking order —
    /// busiest model first, which becomes the bottom segment when rendered).
    private var days: [DayColumn] {
        // Group buckets by day-start.
        var byDay: [Date: [String: TokenUsage]] = [:]
        for b in series.buckets {
            let total = b.usage.total(includingCacheRead: includeCacheInTotals)
            guard total > 0 else { continue }
            byDay[b.start, default: [:]][b.model] = b.usage
        }
        let modelOrder = series.models   // already sorted by total desc
        let indexByModel = Dictionary(uniqueKeysWithValues: modelOrder.enumerated().map { ($0.element, $0.offset) })
        return byDay
            .map { date, usagesByModel in
                let segments: [DayColumn.Segment] = modelOrder.compactMap { model in
                    guard let usage = usagesByModel[model] else { return nil }
                    let total = usage.total(includingCacheRead: includeCacheInTotals)
                    guard total > 0 else { return nil }
                    let solid = total - (includeCacheInTotals ? usage.cacheReadTokens : 0)
                    let cache = includeCacheInTotals ? usage.cacheReadTokens : 0
                    return DayColumn.Segment(
                        model: model,
                        colorIndex: indexByModel[model] ?? 0,
                        solid: max(0, solid),
                        cache: max(0, cache)
                    )
                }
                return DayColumn(date: date, segments: segments)
            }
            .sorted { $0.date < $1.date }
    }

    /// Rounded "nice" Y maximum across the visible days.
    private var yMax: Int {
        let perDayMax = days.map { $0.total }.max() ?? 0
        return Self.niceCeiling(perDayMax)
    }

    /// Y-axis tick values, descending so a top-to-bottom `ForEach` renders
    /// `yMax` first.
    private var yTicks: [Int] {
        let step = max(1, yMax / Self.yTickCount)
        return (0...Self.yTickCount).map { yMax - $0 * step }
    }

    /// Indices into `days` that should carry an X-axis label. Picks ~8 evenly
    /// spaced columns so labels never overlap regardless of period.
    private var xLabelIndices: Set<Int> {
        let n = days.count
        guard n > 0 else { return [] }
        if n <= Self.targetXLabelCount { return Set(0..<n) }
        let step = Double(n - 1) / Double(Self.targetXLabelCount - 1)
        return Set((0..<Self.targetXLabelCount).map { Int((Double($0) * step).rounded()) })
    }

    // MARK: - Subviews

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                yAxis
                plotArea
            }
            .frame(height: Self.chartHeight)
            xAxis
        }
    }

    private var yAxis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(yTicks.enumerated()), id: \.offset) { index, value in
                Text(Format.tokens(value))
                    .font(.sora(8).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if index < yTicks.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: Self.yAxisWidth)
    }

    private var plotArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                gridlines(in: geo.size)
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { _, day in
                        column(for: day, plotHeight: geo.size.height)
                    }
                }
            }
        }
    }

    private func gridlines(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            ForEach(0...Self.yTickCount, id: \.self) { i in
                let y = size.height * CGFloat(i) / CGFloat(Self.yTickCount)
                Rectangle()
                    .fill(Color.stxStroke.opacity(0.5))
                    .frame(height: 0.5)
                    .offset(y: y - 0.25)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func column(for day: DayColumn, plotHeight: CGFloat) -> some View {
        // VStack of segments, smallest model first (top) so the busiest model
        // ends up at the base. Within each segment, the cache portion is
        // drawn above the solid portion (same colour, striped overlay).
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(day.segments.reversed()) { segment in
                let color = ModelPalette.color(at: segment.colorIndex)
                if segment.cache > 0 {
                    stripedRect(color: color)
                        .frame(height: barHeight(segment.cache, plotHeight: plotHeight))
                }
                if segment.solid > 0 {
                    Rectangle()
                        .fill(color)
                        .frame(height: barHeight(segment.solid, plotHeight: plotHeight))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stripedRect(color: Color) -> some View {
        ZStack {
            Rectangle().fill(color)
            DiagonalStripes(spacing: 4)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .clipped()
    }

    private func barHeight(_ tokens: Int, plotHeight: CGFloat) -> CGFloat {
        guard yMax > 0 else { return 0 }
        return plotHeight * CGFloat(tokens) / CGFloat(yMax)
    }

    private var xAxis: some View {
        HStack(alignment: .top, spacing: 0) {
            // Spacer matching the Y-axis column width so labels align with bars.
            Color.clear.frame(width: Self.yAxisWidth + 8)
            HStack(alignment: .top, spacing: 1) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Text(xLabelIndices.contains(index) ? Format.day(day.date) : "")
                        .font(.sora(8).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var placeholder: some View {
        Text("No model activity in this range.")
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: Self.chartHeight, alignment: .center)
    }

    // MARK: - Helpers

    /// Round `value` up to a "nice" number suitable as a chart's Y maximum
    /// (1, 2, 2.5, 5, or 10 × a power of ten). Returns at least 1.
    private static func niceCeiling(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        let magnitude = pow(10.0, floor(log10(Double(value))))
        let normalized = Double(value) / magnitude
        let nice: Double
        switch normalized {
        case ...1: nice = 1
        case ...2: nice = 2
        case ...2.5: nice = 2.5
        case ...5: nice = 5
        default: nice = 10
        }
        return Int((nice * magnitude).rounded(.up))
    }

    // MARK: - Models

    private struct DayColumn: Identifiable {
        let date: Date
        let segments: [Segment]
        var id: Date { date }
        var total: Int { segments.reduce(0) { $0 + $1.solid + $1.cache } }

        struct Segment: Identifiable {
            let model: String
            let colorIndex: Int
            let solid: Int
            let cache: Int
            var id: String { model }
        }
    }
}

#if DEBUG
#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let models = ["claude-opus-4-7", "claude-haiku-4-5", "claude-sonnet-4-6"]
    let buckets: [ModelBucket] = (0..<14).flatMap { day -> [ModelBucket] in
        let start = calendar.date(byAdding: .day, value: -day, to: today)!
        return models.enumerated().map { idx, model in
            ModelBucket(
                model: model,
                start: start,
                usage: TokenUsage(
                    inputTokens: 100_000 * (idx + 1),
                    outputTokens: 800_000 / (idx + 1),
                    cacheReadTokens: 600_000 / (idx + 1),
                    cacheCreation5mTokens: 0,
                    cacheCreation1hTokens: 0
                )
            )
        }
    }
    let series = TrendSeries(granularity: .day, models: models, buckets: buckets)
    return ModelsTrendChart(
        series: series,
        includeCacheInTotals: true,
        displayName: { ClaudeProvider.prettyName(for: $0) }
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
