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

    var body: some View {
        LeaderboardSegmentedChips(
            values: LeaderboardPeriod.allCases,
            selection: $period,
            label: \.chipLabel,
            icon: \.symbolName,
            accessibilityLabel: \.displayName,
            compact: compact
        )
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
        HStack(spacing: 2) {
            ForEach(values) { value in
                chip(value)
            }
        }
        .leaderboardSegmentedBackground()
    }

    private func chip(_ value: Value) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selection = value }
        } label: {
            LeaderboardChipLabel(
                title: value[keyPath: label],
                symbolName: value[keyPath: icon],
                compact: compact,
                isSelected: isSelected
            )
            .leaderboardSelectedSegment(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(value[keyPath: accessibilityLabel]))
    }
}

private struct LeaderboardChipLabel: View {
    let title: String
    let symbolName: String
    let compact: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            Text(title)
                .font(.sora(11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(compact ? 0 : 1)
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .opacity(compact ? 1 : 0)
        }
        .foregroundStyle(isSelected ? .primary : Color.stxMuted)
        .frame(width: compact ? 26 : nil, height: 20)
        .padding(.horizontal, compact ? 5 : 10)
        .padding(.vertical, 5)
    }
}
