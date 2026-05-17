import SwiftUI
import Charts

struct ActivityTrendPanel: View {
    let days: [DayActivity]

    private var points: [ActivityTrendPoint] {
        days.map { ActivityTrendPoint(day: $0.day.start, ratio: $0.assistedRatio) }
    }

    private var hasData: Bool {
        days.contains { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI-ASSISTED SHARE")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("Overlap / editor time")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Text("Daily share of editor focus that overlapped with AI activity.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)

            if hasData {
                StxRule()
                chart
            } else {
                Text("No editor activity recorded in this range.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI-assisted share trend")
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Share", point.ratio)
            )
            .foregroundStyle(Color.stxAccent.opacity(0.16))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Share", point.ratio)
            )
            .foregroundStyle(Color.stxAccent)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(Format.percent(raw))
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXAxis {
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
        .chartLegend(.hidden)
        .frame(height: 220)
        .accessibilityLabel("Daily AI-assisted share")
    }
}

struct ActivityDailyBreakdownPanel: View {
    let days: [DayActivity]

    private var maxEditorSeconds: TimeInterval {
        max(1, days.map(\.ideSeconds).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAILY BREAKDOWN")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("\(activeDayCount) active days")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if days.isEmpty || activeDayCount == 0 {
                Text("No daily activity to list.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
            } else {
                columnHeader
                LazyVStack(spacing: 0) {
                    ForEach(days, id: \.day.start) { day in
                        ActivityDailyBreakdownRow(day: day, maxEditorSeconds: maxEditorSeconds)
                        if day.day.start != days.last?.day.start {
                            StxRule()
                        }
                    }
                }
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily breakdown")
    }

    private var activeDayCount: Int {
        days.filter { !$0.isEmpty }.count
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Day")
                .frame(width: 56, alignment: .leading)
            Text("Assist")
                .frame(width: 44, alignment: .trailing)
            Spacer(minLength: 8)
            Text("Editor")
                .frame(minWidth: 56, alignment: .trailing)
            Text("Overlap")
                .frame(minWidth: 56, alignment: .trailing)
        }
        .font(.sora(9, weight: .medium))
        .foregroundStyle(Color.stxMuted)
        .textCase(.uppercase)
    }
}

private struct ActivityDailyBreakdownRow: View {
    let day: DayActivity
    let maxEditorSeconds: TimeInterval

    private var editorWidthRatio: Double {
        day.ideSeconds / max(1, maxEditorSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(Format.day(day.day.start))
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 56, alignment: .leading)

                Text(Format.percent(day.assistedRatio))
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .trailing)

                Spacer(minLength: 8)

                Text(Format.duration(day.ideSeconds))
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 56, alignment: .trailing)

                Text(Format.duration(day.overlapSeconds))
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 56, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: proxy.size.width * CGFloat(editorWidthRatio))

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.stxAccent)
                        .frame(width: proxy.size.width * CGFloat(day.assistedRatio) * CGFloat(editorWidthRatio))
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.day(day.day.start)), \(Format.percent(day.assistedRatio)) AI-assisted, \(Format.duration(day.ideSeconds)) editor time")
    }
}

private struct ActivityTrendPoint: Identifiable {
    let day: Date
    let ratio: Double

    var id: TimeInterval {
        day.timeIntervalSinceReferenceDate
    }
}

#if DEBUG
#Preview {
    ActivityTrendPanel(days: [])
        .padding(24)
        .frame(width: 760)
        .background(Color.stxBackground)
}
#endif
