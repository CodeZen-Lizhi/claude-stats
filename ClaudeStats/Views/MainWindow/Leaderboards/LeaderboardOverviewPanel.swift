import SwiftUI
import ClaudeStatsIconography

struct LeaderboardTitleHeader: View {
    let isLoadingScores: Bool
    let isSyncBusy: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            titleText
            Spacer(minLength: 12)
            headerActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEADERBOARDS")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Global rankings")
                .font(.sora(24, weight: .semibold))
                .lineLimit(1)
            Text("Aggregate usage scores in shared UTC windows.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            LeaderboardIconActionButton(
                systemName: "arrow.clockwise",
                help: "Sync and refresh",
                isDisabled: isLoadingScores || isSyncBusy,
                action: onRefresh
            )

            if isLoadingScores || isSyncBusy {
                ProgressView()
                    .controlSize(.small)
                    .help(isSyncBusy ? "Syncing leaderboard scores" : "Loading leaderboard scores")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 18)
    }
}

struct LeaderboardOverviewPanel: View {
    @Binding var metric: LeaderboardMetric
    @Binding var period: LeaderboardPeriod
    @Binding var selectedDailyDate: Date

    let scores: [LeaderboardScore]
    let topScore: Int64
    let currentUserHash: String?
    let syncStatusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            summaryStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlsRows(compactMetric: false, compactPeriod: false)
            controlsRows(compactMetric: true, compactPeriod: false)
            controlsRows(compactMetric: true, compactPeriod: true)
            stackedControls(compactMetric: false, compactPeriod: false)
            stackedControls(compactMetric: true, compactPeriod: true)
        }
    }

    private func controlsRows(compactMetric: Bool, compactPeriod: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                LeaderboardMetricChips(metric: $metric, compact: compactMetric)
                Spacer(minLength: 12)
                LeaderboardDailyPeriodControl(
                    period: $period,
                    selectedDate: $selectedDailyDate
                )
                LeaderboardPeriodChips(
                    period: $period,
                    compact: compactPeriod,
                    values: [.week, .month, .allTime]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stackedControls(compactMetric: Bool, compactPeriod: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LeaderboardMetricChips(metric: $metric, compact: compactMetric)
            HStack(alignment: .center, spacing: 10) {
                LeaderboardDailyPeriodControl(
                    period: $period,
                    selectedDate: $selectedDailyDate
                )
                LeaderboardPeriodChips(
                    period: $period,
                    compact: compactPeriod,
                    values: [.week, .month, .allTime]
                )
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryStrip: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            LeaderboardSummaryCard(label: "Entries", value: scores.isEmpty ? "--" : "\(scores.count)")
            LeaderboardSummaryCard(label: "Top score", value: topScore > 0 ? LeaderboardFormat.score(topScore, metric: metric) : "--")
            LeaderboardSummaryCard(label: "Your rank", value: yourRankLabel)
            LeaderboardSummaryCard(label: "Sync", value: syncStatusText, animatesNumericValue: false)
        }
    }

    private var yourRankLabel: String {
        guard let currentUserHash,
              let rank = scores.first(where: { $0.userHash == currentUserHash })?.rank else {
            return "--"
        }
        return "#\(rank)"
    }
}

private struct LeaderboardIconActionButton: View {
    let systemName: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FunctionalIconView(systemSymbolName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.stxAccent.opacity(0.35) : Color.stxAccent)
                .frame(width: 42, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.stxAccent.opacity(0.08))
        )
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct LeaderboardSummaryCard: View {
    let label: String
    let value: String
    var animatesNumericValue = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.sora(8, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(14, weight: .semibold).monospacedDigit())
                .modifier(NumericValueTransitionIfEnabled(enabled: animatesNumericValue, value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .frame(height: 19, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}
