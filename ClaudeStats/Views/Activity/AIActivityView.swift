import SwiftUI
import Charts
import AppKit

/// The "Activity" pane: lines up macOS Screen Time editor-focus time against
/// Claude Code activity, on a day timeline (Tyme-style) plus a multi-day trend
/// of the AI-assisted share. Reads `knowledgeC.db` — needs Full Disk Access.
struct AIActivityView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = AIActivityViewModel()

    private struct ReloadKey: Equatable {
        let token: UInt64
        let lastRefreshed: Date?
        let bundleIDs: Set<String>
    }

    var body: some View {
        @Bindable var vm = vm
        let bundleIDs = env.preferences.effectiveIDEBundleIDs
        let key = ReloadKey(token: vm.reloadToken,
                            lastRefreshed: env.store.lastRefreshedAt,
                            bundleIDs: bundleIDs)

        FadingScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                if vm.permissionState == .needsFullDiskAccess {
                    permissionGate
                } else if vm.range.isTrend {
                    trendSection
                } else {
                    daySection
                }
            }
            .padding(14)
        }
        .task(id: key) {
            await vm.reload(sessions: env.store.sessions, bundleIDs: bundleIDs)
        }
        .onAppear { vm.refreshPermissionState() }
    }

    // MARK: Header

    private var headerRow: some View {
        @Bindable var vm = vm
        return HStack(spacing: 10) {
            if vm.range == .day {
                HStack(spacing: 0) {
                    stepButton(systemName: "chevron.left") { vm.stepDay(-1) }
                    BracketBox(spacing: 6) {
                        Text(Format.day(vm.selectedDay).uppercased())
                            .font(.sora(11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    stepButton(systemName: "chevron.right", disabled: !vm.canStepForward) { vm.stepDay(1) }
                }
            } else {
                BracketBox(spacing: 6) {
                    Text("LAST \(vm.range.dayCount) DAYS")
                        .font(.sora(11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
            if vm.isLoading { ProgressView().controlSize(.mini) }
            HStack(spacing: 8) {
                ForEach(ActivityRange.allCases) { r in
                    RangeChip(label: r.shortLabel, isSelected: vm.range == r) { vm.range = r }
                }
            }
        }
    }

    private func stepButton(systemName: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.stxMuted.opacity(0.35) : Color.stxMuted)
        .disabled(disabled)
    }

    private struct RangeChip: View {
        let label: String
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                VStack(spacing: 3) {
                    Text(label.uppercased())
                        .font(.sora(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? .primary : (hovering ? Color.primary : Color.primary.opacity(0.40)))
                    Rectangle()
                        .fill(Color.stxAccent)
                        .frame(height: 1.5)
                        .scaleEffect(x: isSelected ? 1 : 0, anchor: .center)
                }
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: isSelected)
        }
    }

    // MARK: Permission gate

    private var permissionGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FULL DISK ACCESS REQUIRED")
                .font(.sora(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
            Text("Claude Stats reads macOS Screen Time (the Knowledge database) to see when your editor was focused. macOS keeps that file behind Full Disk Access — grant it, then come back to this tab.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open Full Disk Access settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Re-check") { vm.bumpReload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.sora(10))
        }
        .stxPanel(12)
    }

    // MARK: Single-day section

    @ViewBuilder
    private var daySection: some View {
        let activity = vm.dayActivity
        summaryGrid(activity)
        timelinePanel(activity)
        compositionPanel(activity)
    }

    private func summaryGrid(_ a: DayActivity?) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell("Editor time", Format.duration(a?.ideSeconds ?? 0))
                statCell("AI active", Format.duration(a?.aiSeconds ?? 0))
            }
            GridRow {
                statCell("Overlap", Format.duration(a?.overlapSeconds ?? 0))
                statCell("AI-assisted", a.map { Format.percent($0.assistedRatio) } ?? "—")
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

    // MARK: Day timeline

    private struct TimelineSegment: Identifiable {
        enum Kind { case ide, ai, overlap }
        let id = UUID()
        let kind: Kind
        let interval: DateInterval
    }

    private func timelineSegments(_ a: DayActivity) -> [TimelineSegment] {
        a.ideIntervals.map { TimelineSegment(kind: .ide, interval: $0) }
        + a.aiIntervals.map { TimelineSegment(kind: .ai, interval: $0) }
        + a.overlapIntervals.map { TimelineSegment(kind: .overlap, interval: $0) }
    }

    /// `[floor(earliest, hour), ceil(latest, hour)]`, or `nil` if the day is empty.
    private func timelineDomain(_ a: DayActivity) -> ClosedRange<Date>? {
        let all = a.ideIntervals + a.aiIntervals
        guard let lo = all.map(\.start).min(), let hi = all.map(\.end).max() else { return nil }
        let cal = Calendar.current
        let start = cal.dateInterval(of: .hour, for: lo)?.start ?? lo
        let endHour = cal.dateInterval(of: .hour, for: hi)?.end ?? hi
        return start...max(endHour, start.addingTimeInterval(3600))
    }

    private func axisStrideHours(_ domain: ClosedRange<Date>) -> Int {
        let hours = domain.upperBound.timeIntervalSince(domain.lowerBound) / 3600
        if hours <= 8 { return 1 }
        if hours <= 16 { return 2 }
        return 3
    }

    private static let ideBaseColor = Color.primary.opacity(0.26)
    private static let aiBaseColor = Color.stxAccent.opacity(0.40)
    private static let overlapColor = Color.stxAccent

    @ViewBuilder
    private func timelinePanel(_ a: DayActivity?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("DAY TIMELINE")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
            }
            Text("EDITOR FOCUS vs AI ACTIVE · BY CLOCK HOUR")
                .font(.sora(9))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)

            if let a, !a.isEmpty, let domain = timelineDomain(a) {
                timelineLegend
                StxRule()
                timelineChart(a, domain: domain)
            } else {
                Text("No editor or AI activity recorded for this day.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .stxPanel(12)
    }

    private var timelineLegend: some View {
        HStack(spacing: 14) {
            legendChip("IDE FOCUS", Self.ideBaseColor)
            legendChip("AI ACTIVE", Self.aiBaseColor)
            legendChip("BOTH", Self.overlapColor)
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
        }
    }

    private func timelineChart(_ a: DayActivity, domain: ClosedRange<Date>) -> some View {
        let stride = axisStrideHours(domain)
        return Chart(timelineSegments(a)) { seg in
            RectangleMark(
                xStart: .value("Start", seg.interval.start),
                xEnd: .value("End", seg.interval.end),
                yStart: .value("Lo", laneRange(seg.kind).lowerBound),
                yEnd: .value("Hi", laneRange(seg.kind).upperBound)
            )
            .foregroundStyle(color(for: seg.kind))
            .cornerRadius(1)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: stride)) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour())
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 96)
    }

    private func laneRange(_ kind: TimelineSegment.Kind) -> ClosedRange<Double> {
        switch kind {
        case .ai: return 0.06...0.44      // bottom lane
        case .ide: return 0.56...0.94     // top lane
        case .overlap: return 0.06...0.94 // spans both — stitches them together
        }
    }

    private func color(for kind: TimelineSegment.Kind) -> Color {
        switch kind {
        case .ide: return Self.ideBaseColor
        case .ai: return Self.aiBaseColor
        case .overlap: return Self.overlapColor
        }
    }

    // MARK: Composition bar

    private func compositionPanel(_ a: DayActivity?) -> some View {
        let overlap = a?.overlapSeconds ?? 0
        let solo = a?.soloIDESeconds ?? 0
        let aiOnly = a?.aiOnlySeconds ?? 0
        let total = max(1, overlap + solo + aiOnly)
        let parts: [(String, Color, TimeInterval)] = [
            ("AI-assisted coding", Self.overlapColor, overlap),
            ("Solo coding", Self.ideBaseColor, solo),
            ("AI without editor", Self.aiBaseColor, aiOnly),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("HOW THE TIME SPLIT")
                .font(.sora(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.stxMuted)
            if overlap + solo + aiOnly <= 0 {
                Text("Nothing to break down for this day.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
            } else {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            Rectangle()
                                .fill(part.1)
                                .frame(width: max(part.2 > 0 ? 2 : 0, geo.size.width * CGFloat(part.2 / total)))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 6)
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    HStack(spacing: 6) {
                        Rectangle().fill(part.1).frame(width: 7, height: 7)
                        Text(part.0)
                            .font(.sora(10))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(Format.duration(part.2))
                            .font(.sora(10).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
    }

    // MARK: Multi-day trend

    private struct TrendPoint: Identifiable {
        let day: Date
        let ratio: Double
        var id: TimeInterval { day.timeIntervalSinceReferenceDate }
    }

    @ViewBuilder
    private var trendSection: some View {
        let points = vm.trend.map { TrendPoint(day: $0.day.start, ratio: $0.assistedRatio) }
        let hasData = vm.trend.contains { !$0.isEmpty }
        let avgRatio = trendAverage()

        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell("Editor time", Format.duration(vm.trend.reduce(0) { $0 + $1.ideSeconds }))
                statCell("AI active", Format.duration(vm.trend.reduce(0) { $0 + $1.aiSeconds }))
            }
            GridRow {
                statCell("Overlap", Format.duration(vm.trend.reduce(0) { $0 + $1.overlapSeconds }))
                statCell("Avg AI-assisted", avgRatio.map { Format.percent($0) } ?? "—")
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("AI-ASSISTED SHARE · PER DAY")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            Text("OVERLAP ÷ EDITOR TIME, EACH DAY")
                .font(.sora(9))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if hasData {
                StxRule()
                trendChart(points)
            } else {
                Text("No editor activity recorded in this range.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .stxPanel(12)
    }

    private func trendAverage() -> Double? {
        let withEditor = vm.trend.filter { $0.ideSeconds > 0 }
        guard !withEditor.isEmpty else { return nil }
        let ide = withEditor.reduce(0) { $0 + $1.ideSeconds }
        let overlap = withEditor.reduce(0) { $0 + $1.overlapSeconds }
        return ide > 0 ? overlap / ide : nil
    }

    private func trendChart(_ points: [TrendPoint]) -> some View {
        Chart(points) { p in
            AreaMark(x: .value("Day", p.day, unit: .day), y: .value("Share", p.ratio))
                .foregroundStyle(Color.stxAccent.opacity(0.16))
            LineMark(x: .value("Day", p.day, unit: .day), y: .value("Share", p.ratio))
                .foregroundStyle(Color.stxAccent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Format.percent(v)).font(.sora(8)).foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXAxis {
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
        .chartLegend(.hidden)
        .frame(height: 150)
    }
}

#if DEBUG
#Preview("Activity") {
    AIActivityView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
}
#endif
