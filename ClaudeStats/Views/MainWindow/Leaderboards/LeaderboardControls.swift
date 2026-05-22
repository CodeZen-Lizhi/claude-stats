import SwiftUI

struct LeaderboardMetricChips: View {
    @Binding var metric: LeaderboardMetric
    let compact: Bool

    var body: some View {
        LeaderboardSegmentedChips(
            values: LeaderboardMetric.allCases,
            selection: $metric,
            label: \.shortLabel,
            icon: \.symbolName,
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
            icon: \.symbolName,
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
        dayStepper
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily leaderboard date")
    }

    private var dayStepper: some View {
        HStack(spacing: 4) {
            stepButton(systemName: "chevron.left", help: "Previous UTC day") {
                stepDay(-1)
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    period = .day
                }
            } label: {
                Text(LeaderboardDailyDateNavigator.label(for: selectedDate))
                    .font(.sora(11, weight: .medium).monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                    .lineLimit(1)
                    .frame(minWidth: 70)
                    .frame(height: 30)
                    .leaderboardSelectedSegment(isSelected)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show selected UTC day")
            .accessibilityLabel("Selected UTC day")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            stepButton(systemName: "chevron.right", disabled: !canStepForward, help: "Next UTC day") {
                stepDay(1)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func stepButton(systemName: String,
                            disabled: Bool = false,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(disabled ? Color.stxMuted.opacity(0.35) : Color.stxMuted)
                .frame(width: 24, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
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
    let icon: KeyPath<Value, String>
    let accessibilityLabel: KeyPath<Value, String>
    let compact: Bool

    var body: some View {
        PillSegmentedBar(
            values,
            selection: $selection,
            accessibilityLabel: { $0[keyPath: accessibilityLabel] }
        ) { value, isSelected in
            LeaderboardChipLabel(
                title: value[keyPath: label],
                symbolName: value[keyPath: icon],
                compact: compact
            )
        }
    }
}

private struct LeaderboardChipLabel: View {
    let title: String
    let symbolName: String
    let compact: Bool

    var body: some View {
        ZStack {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(compact ? 0 : 1)
            Image(systemName: symbolName)
                .opacity(compact ? 1 : 0)
        }
        .frame(width: compact ? 26 : nil)
    }
}
