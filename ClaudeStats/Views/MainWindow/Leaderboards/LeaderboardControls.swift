import SwiftUI

struct LeaderboardMetricChips: View {
    @Binding var metric: LeaderboardMetric
    let compact: Bool

    var body: some View {
        LeaderboardSegmentedChips(
            values: LeaderboardMetric.allCases,
            selection: $metric,
            label: \.shortLabel,
            accessibilityLabel: \.displayName,
            compact: compact
        )
    }
}

struct LeaderboardPeriodChips: View {
    @Binding var period: LeaderboardPeriod
    let compact: Bool
    var values: [LeaderboardPeriod] = LeaderboardPeriod.allCases

    var body: some View {
        LeaderboardSegmentedChips(
            values: values,
            selection: $period,
            label: \.chipLabel,
            accessibilityLabel: \.displayName,
            compact: compact
        )
    }
}

struct LeaderboardDailyPeriodControl: View {
    @Binding var period: LeaderboardPeriod
    @Binding var selectedDate: Date

    private var isSelected: Bool {
        period == .day
    }

    private var canStepForward: Bool {
        LeaderboardDailyDateNavigator.canStepForward(from: selectedDate)
    }

    var body: some View {
        PillTimeStepperBar(
            canStepForward: canStepForward,
            isCenterSelected: isSelected,
            previousHelp: "Previous UTC day",
            nextHelp: "Next UTC day",
            centerHelp: "Show selected UTC day",
            centerAccessibilityLabel: "Selected UTC day",
            accessibilityLabel: "Daily leaderboard date",
            onPrevious: {
                stepDay(-1)
            },
            onNext: {
                stepDay(1)
            },
            onCenter: {
                withAnimation(.easeOut(duration: 0.18)) {
                    period = .day
                }
            }
        ) { _ in
            Text(LeaderboardDailyDateNavigator.label(for: selectedDate))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepDay(_ offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedDate = LeaderboardDailyDateNavigator.stepped(from: selectedDate, by: offset)
            period = .day
        }
    }
}

private struct LeaderboardSegmentedChips<Value: Identifiable & Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: KeyPath<Value, String>
    let accessibilityLabel: KeyPath<Value, String>
    let compact: Bool

    var body: some View {
        PillSegmentedBar(
            values,
            selection: $selection,
            style: .leaderboard(compact: compact),
            accessibilityLabel: { $0[keyPath: accessibilityLabel] }
        ) { value, _ in
            LeaderboardChipLabel(
                title: value[keyPath: label]
            )
        }
    }
}

private struct LeaderboardChipLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private extension PillSegmentedBarStyle {
    static func leaderboard(compact: Bool) -> PillSegmentedBarStyle {
        var style = PillSegmentedBarStyle.standard
        style.itemHorizontalPadding = compact ? 8 : 12
        return style
    }
}
