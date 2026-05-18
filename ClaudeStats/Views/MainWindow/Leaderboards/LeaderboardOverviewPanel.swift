import SwiftUI

struct LeaderboardTitleHeader: View {
    var body: some View {
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
}

struct LeaderboardOverviewPanel: View {
    @Binding var metric: LeaderboardMetric
    @Binding var period: LeaderboardPeriod

    let scores: [LeaderboardScore]
    let topScore: Int64
    let currentUserHash: String?
    let syncStatusText: String
    let isLoadingScores: Bool
    let isSyncBusy: Bool
    let onRefresh: () -> Void
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            summaryStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                metricAndActionsRow(compactMetric: false)
                metricAndActionsRow(compactMetric: true)
            }
            ViewThatFits(in: .horizontal) {
                LeaderboardPeriodChips(period: $period, compact: false)
                LeaderboardPeriodChips(period: $period, compact: true)
            }
        }
    }

    private func metricAndActionsRow(compactMetric: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            LeaderboardMetricChips(metric: $metric, compact: compactMetric)
            Spacer(minLength: 12)
            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if isLoadingScores {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading leaderboard scores")
            }
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .disabled(isLoadingScores)

            Button(action: onSync) {
                Label("Sync mine", systemImage: "icloud.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .disabled(isSyncBusy)
        }
        .font(.sora(11, weight: .medium))
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
            LeaderboardSummaryCard(label: "Sync", value: syncStatusText)
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

private struct LeaderboardSummaryCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.sora(8, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(14, weight: .semibold).monospacedDigit())
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
