import SwiftUI

struct LeaderboardsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var metric: LeaderboardMetric = .tokensWithCache
    @State private var period: LeaderboardPeriod = .day

    private var reloadID: String {
        "\(metric.rawValue)-\(period.rawValue)-\(env.preferences.leaderboardsEnabled)"
    }

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if env.preferences.leaderboardsEnabled {
                    controls
                    statusPanel
                    scoresPanel
                } else {
                    disabledPanel
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .task(id: reloadID) {
            guard env.preferences.leaderboardsEnabled else { return }
            await env.leaderboards.loadScores(metric: metric, period: period)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboards")
                .font(.sora(28, weight: .semibold))
            Text("Global CloudKit rankings for aggregate usage. Periods use UTC so every user competes in the same window.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Metric", selection: $metric) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    Text(metric.shortLabel).tag(metric)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Picker("Period", selection: $period) {
                ForEach(LeaderboardPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Spacer()

            Button("Refresh") {
                Task { await env.leaderboards.loadScores(metric: metric, period: period) }
            }
            .disabled(env.leaderboards.isLoadingScores)

            Button("Sync mine") {
                Task {
                    await env.leaderboards.syncNow()
                    await env.leaderboards.loadScores(metric: metric, period: period)
                }
            }
            .disabled(env.leaderboards.syncStatus == .syncing || env.leaderboards.syncStatus == .checkingAccount)
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 18) {
            stat(label: "Metric", value: metric.displayName)
            stat(label: "Period", value: "\(period.displayName) · \(env.leaderboards.lastLoadedPeriodKey ?? "UTC")")
            stat(label: "Sync", value: env.leaderboards.syncStatus.displayText)
        }
        .stxPanel(14)
    }

    private var scoresPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top 100")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                if env.leaderboards.isLoadingScores {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.bottom, 10)

            if let error = env.leaderboards.scoreError {
                emptyState(error)
            } else if env.leaderboards.scores.isEmpty && !env.leaderboards.isLoadingScores {
                emptyState("No scores for this UTC period yet.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(env.leaderboards.scores) { score in
                        scoreRow(score)
                        if score.id != env.leaderboards.scores.last?.id {
                            StxRule()
                        }
                    }
                }
            }
        }
        .stxPanel(14)
    }

    private var disabledPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leaderboards are off")
                .font(.sora(15, weight: .semibold))
            Text("Enable them in Settings ▸ Leaderboards, choose a public nickname, then sync your aggregate scores to CloudKit.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
            Button("Open Settings") {
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
            }
        }
        .stxPanel(16)
    }

    private func scoreRow(_ score: LeaderboardScore) -> some View {
        HStack(spacing: 12) {
            Text("#\(score.rank ?? 0)")
                .font(.sora(12, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(score.nickname)
                    .font(.sora(13, weight: .medium))
                    .lineLimit(1)
                Text("Updated \(Format.relativeDate(score.updatedAt))")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer()
            Text(format(score.score, metric: score.metric))
                .font(.sora(14, weight: .semibold))
        }
        .padding(.vertical, 10)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(13, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private func format(_ score: Int64, metric: LeaderboardMetric) -> String {
        switch metric {
        case .tokensWithCache, .tokensWithoutCacheRead:
            return Format.tokens(Int(clamping: score))
        case .activityMinutes:
            return Format.duration(TimeInterval(score * 60))
        }
    }
}

#if DEBUG
#Preview {
    LeaderboardsView()
        .environment(AppEnvironment.preview())
        .frame(width: 780, height: 620)
        .padding()
}
#endif
