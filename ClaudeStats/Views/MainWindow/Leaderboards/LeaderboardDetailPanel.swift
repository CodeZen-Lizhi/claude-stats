import Charts
import SwiftUI

struct LeaderboardDetailPanel: View {
    let score: LeaderboardScore?
    let scores: [LeaderboardScore]
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let topScore: Int64
    let currentUserScore: LeaderboardScore?
    let currentUserHash: String?
    let history: [LeaderboardScoreHistoryPoint]
    let isLoadingHistory: Bool
    let historyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let score {
                profilePanel(score)
                statsPanel(score)
                historyPanel(score)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                emptyPanel
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func profilePanel(_ score: LeaderboardScore) -> some View {
        HStack(alignment: .center, spacing: 14) {
            BeamAvatarView(seed: LeaderboardFormat.avatarSeed(for: score), size: 58)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(score.nickname)
                        .font(.sora(22, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isCurrentUser(score) {
                        Text("YOU")
                            .font(.sora(9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(Color.stxAccent)
                    }
                }
                HStack(spacing: 8) {
                    Text(score.rank.map { "#\($0)" } ?? "Unranked")
                    Text("·")
                    Text(period.displayName)
                    Text("·")
                    Text(metric.displayName)
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                Text("Updated \(Format.relativeDate(score.updatedAt))")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func statsPanel(_ score: LeaderboardScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(detailMetrics(for: score)) { metric in
                    LeaderboardDetailMetricCell(metric: metric)
                }
            }
        }
        .mainWindowPanel(padding: 16)
    }

    private func historyPanel(_ score: LeaderboardScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("HISTORY")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer(minLength: 8)
                Text(historyCaption)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if period == .allTime {
                LeaderboardHistoryMessage("All-time totals do not have a period trend.")
            } else if score.userHash == nil {
                LeaderboardHistoryMessage("History is unavailable for this legacy score.")
            } else if isLoadingHistory {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else if let historyError {
                LeaderboardHistoryMessage(historyError)
            } else if history.isEmpty || history.allSatisfy({ $0.score == 0 }) {
                LeaderboardHistoryMessage("No historical scores for this user in these windows.")
            } else {
                LeaderboardHistoryChart(points: history, metric: metric, period: period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Leaderboard history")
    }

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No user selected")
                .font(.sora(16, weight: .semibold))
            Text("Pick a rank on the left to inspect the user's current score and trend.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .mainWindowPanel(padding: 16)
    }

    private var historyCaption: String {
        switch period {
        case .day: "Last 14 days"
        case .week: "Last 12 weeks"
        case .month: "Last 12 months"
        case .allTime: "All-time"
        }
    }

    private func detailMetrics(for score: LeaderboardScore) -> [LeaderboardDetailMetric] {
        var metrics = [
            LeaderboardDetailMetric(label: "Score", value: LeaderboardFormat.score(score.score, metric: metric)),
            LeaderboardDetailMetric(label: "Rank", value: rankLabel(for: score)),
            LeaderboardDetailMetric(label: "Gap to #1", value: gapToTopLabel(for: score)),
            LeaderboardDetailMetric(label: "Top share", value: topShareLabel(for: score)),
        ]
        if let vsYou = vsYouLabel(for: score) {
            metrics.append(LeaderboardDetailMetric(label: "Vs you", value: vsYou))
        }
        return metrics
    }

    private func rankLabel(for score: LeaderboardScore) -> String {
        guard let rank = score.rank else { return "-- / \(scores.count)" }
        return "#\(rank) / \(scores.count)"
    }

    private func gapToTopLabel(for score: LeaderboardScore) -> String {
        guard topScore > 0 else { return "--" }
        let delta = max(topScore - score.score, 0)
        return delta == 0 ? "Leader" : LeaderboardFormat.score(delta, metric: metric)
    }

    private func topShareLabel(for score: LeaderboardScore) -> String {
        guard topScore > 0 else { return "--" }
        return Format.percent(Double(score.score) / Double(topScore))
    }

    private func vsYouLabel(for score: LeaderboardScore) -> String? {
        guard let currentUserScore,
              !isCurrentUser(score) else {
            return nil
        }
        let delta = score.score - currentUserScore.score
        if delta == 0 { return "Even" }
        let prefix = delta > 0 ? "+" : "-"
        return "\(prefix)\(LeaderboardFormat.score(abs(delta), metric: metric))"
    }

    private func isCurrentUser(_ score: LeaderboardScore) -> Bool {
        guard let currentUserHash else { return false }
        return score.userHash == currentUserHash
    }
}

private struct LeaderboardDetailMetric: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct LeaderboardDetailMetricCell: View {
    let metric: LeaderboardDetailMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label.uppercased())
                .font(.sora(8, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(metric.value)
                .font(.sora(17, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LeaderboardHistoryChart: View {
    let points: [LeaderboardScoreHistoryPoint]
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod

    private var yMax: Double {
        max(1, Double(points.map(\.score).max() ?? 0))
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Window", point.startUTC, unit: xUnit),
                y: .value("Score", Double(point.score))
            )
            .foregroundStyle(Color.stxAccent.opacity(0.16))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Window", point.startUTC, unit: xUnit),
                y: .value("Score", Double(point.score))
            )
            .foregroundStyle(Color.stxAccent)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(LeaderboardFormat.score(Int64(raw.rounded()), metric: metric))
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        xAxisLabel(for: date)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 180)
        .accessibilityLabel("\(metric.displayName) history")
    }

    private var xUnit: Calendar.Component {
        switch period {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .allTime: .day
        }
    }

    @ViewBuilder
    private func xAxisLabel(for date: Date) -> some View {
        switch period {
        case .month:
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.sora(8))
                .foregroundStyle(Color.stxMuted)
        case .day, .week, .allTime:
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.sora(8))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct LeaderboardHistoryMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }
}
