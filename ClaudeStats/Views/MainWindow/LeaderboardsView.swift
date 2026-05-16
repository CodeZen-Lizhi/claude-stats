import SwiftUI

struct LeaderboardsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var metric: LeaderboardMetric = .tokensWithCache
    @State private var period: LeaderboardPeriod = .day

    private var reloadID: String {
        "\(metric.rawValue)-\(period.rawValue)-\(env.preferences.leaderboardsEnabled)"
    }

    private var scores: [LeaderboardScore] {
        env.leaderboards.scores
    }

    private var topScore: Int64 {
        scores.first?.score ?? 0
    }

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if env.preferences.leaderboardsEnabled {
                    summaryStrip
                    podiumSection
                    scoresPanel
                } else {
                    disabledPanel
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: reloadID) {
            guard env.preferences.leaderboardsEnabled else { return }
            await env.leaderboards.loadScores(metric: metric, period: period)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
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
            Spacer(minLength: 12)
            if env.preferences.leaderboardsEnabled {
                headerControls
            }
        }
    }

    private var headerControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                LeaderboardMetricChips(metric: $metric)
                LeaderboardPeriodChips(period: $period)
            }
            HStack(spacing: 8) {
                if env.leaderboards.isLoadingScores {
                    ProgressView()
                        .controlSize(.small)
                        .help("Loading leaderboard scores")
                }
                Button {
                    Task { await env.leaderboards.loadScores(metric: metric, period: period) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(env.leaderboards.isLoadingScores)

                Button {
                    Task {
                        await env.leaderboards.syncNow()
                        await env.leaderboards.loadScores(metric: metric, period: period)
                    }
                } label: {
                    Label("Sync mine", systemImage: "icloud.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(isSyncBusy)
            }
            .font(.sora(11, weight: .medium))
        }
    }

    private var summaryStrip: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                LeaderboardSummaryCard(label: "Entries", value: scores.isEmpty ? "--" : "\(scores.count)")
                LeaderboardSummaryCard(label: "Top score", value: topScore > 0 ? format(topScore, metric: metric) : "--")
                LeaderboardSummaryCard(label: "Your rank", value: yourRankLabel)
                LeaderboardSummaryCard(label: "Sync", value: env.leaderboards.syncStatus.displayText)
            }
        }
    }

    @ViewBuilder
    private var podiumSection: some View {
        if let error = env.leaderboards.scoreError {
            LeaderboardNotice(message: error)
        } else if scores.isEmpty && !env.leaderboards.isLoadingScores {
            LeaderboardNotice(message: env.leaderboards.scoreEmptyMessage ?? "No scores for this UTC period yet.")
        } else if !scores.isEmpty {
            HStack(alignment: .bottom, spacing: 12) {
                LeaderboardPodiumSlot(
                    score: scores[safe: 1],
                    fallbackRank: 2,
                    topScore: topScore,
                    height: 118,
                    isCurrentUser: isCurrentUser(scores[safe: 1])
                )
                LeaderboardPodiumSlot(
                    score: scores[safe: 0],
                    fallbackRank: 1,
                    topScore: topScore,
                    height: 148,
                    isFeatured: true,
                    isCurrentUser: isCurrentUser(scores[safe: 0])
                )
                LeaderboardPodiumSlot(
                    score: scores[safe: 2],
                    fallbackRank: 3,
                    topScore: topScore,
                    height: 108,
                    isCurrentUser: isCurrentUser(scores[safe: 2])
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scoresPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOP 100")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                if let periodKey = env.leaderboards.lastLoadedPeriodKey {
                    Text(periodKey)
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer()
                Text(metric.displayName)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)

            if scores.dropFirst(3).isEmpty {
                Text(scores.count <= 3 ? "The podium has everyone for this window." : "No additional ranks.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(scores.dropFirst(3))) { score in
                        LeaderboardScoreRow(
                            score: score,
                            formattedScore: format(score.score, metric: score.metric),
                            topScore: topScore,
                            isCurrentUser: isCurrentUser(score)
                        )
                        if score.id != scores.last?.id {
                            StxRule()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private var disabledPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.stxAccent)
            Text("Leaderboards are off")
                .font(.sora(16, weight: .semibold))
            Text("Enable them in Settings, choose a public nickname, then sync aggregate scores and a generated Beam avatar to CloudKit.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
            } label: {
                BracketBox(spacing: 5) {
                    Label("OPEN SETTINGS", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10, weight: .medium))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxAccent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private var isSyncBusy: Bool {
        env.leaderboards.syncStatus == .syncing
            || env.leaderboards.syncStatus == .checkingAccount
            || env.leaderboards.isSavingProfile
    }

    private var yourRankLabel: String {
        if let rank = env.leaderboards.currentUserScore?.rank {
            return "#\(rank)"
        }
        return "--"
    }

    private func isCurrentUser(_ score: LeaderboardScore?) -> Bool {
        guard let score else { return false }
        return isCurrentUser(score)
    }

    private func isCurrentUser(_ score: LeaderboardScore) -> Bool {
        guard let currentUserHash = env.leaderboards.currentUserHash else { return false }
        return score.userHash == currentUserHash
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

private struct LeaderboardMetricChips: View {
    @Binding var metric: LeaderboardMetric

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LeaderboardMetric.allCases) { value in
                chip(value)
            }
        }
        .segmentedBackground()
    }

    private func chip(_ value: LeaderboardMetric) -> some View {
        let isSelected = metric == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { metric = value }
        } label: {
            Text(value.shortLabel)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .selectedSegment(isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LeaderboardPeriodChips: View {
    @Binding var period: LeaderboardPeriod

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LeaderboardPeriod.allCases) { value in
                chip(value)
            }
        }
        .segmentedBackground()
    }

    private func chip(_ value: LeaderboardPeriod) -> some View {
        let isSelected = period == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { period = value }
        } label: {
            Text(label(for: value))
                .font(.sora(11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .selectedSegment(isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func label(for period: LeaderboardPeriod) -> String {
        switch period {
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .allTime: "All"
        }
    }
}

private struct LeaderboardSummaryCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.sora(9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(17, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(height: 22, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private struct LeaderboardPodiumSlot: View {
    let score: LeaderboardScore?
    let fallbackRank: Int
    let topScore: Int64
    let height: CGFloat
    var isFeatured = false
    let isCurrentUser: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if let score {
                BeamAvatarView(seed: avatarSeed(for: score), size: isFeatured ? 58 : 48)
                HStack(spacing: 5) {
                    Text("#\(score.rank ?? fallbackRank)")
                        .font(.sora(isFeatured ? 18 : 14, weight: .semibold).monospacedDigit())
                    if isCurrentUser {
                        Text("YOU")
                            .font(.sora(8, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.stxAccent)
                    }
                }
                Text(score.nickname)
                    .font(.sora(isFeatured ? 14 : 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedScore(score))
                    .font(.sora(isFeatured ? 16 : 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isFeatured ? Color.stxAccent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("#\(fallbackRank)")
                    .font(.sora(14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                Text("Waiting")
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(slotBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isCurrentUser ? Color.stxAccent : Color.stxStroke, lineWidth: isCurrentUser ? 1.5 : 1)
        )
    }

    private var slotBackground: Color {
        if isCurrentUser { return Color.stxAccent.opacity(0.08) }
        return isFeatured ? Color.stxPanel : Color.stxPanel.opacity(0.76)
    }

    private func formattedScore(_ score: LeaderboardScore) -> String {
        switch score.metric {
        case .tokensWithCache, .tokensWithoutCacheRead:
            return Format.tokens(Int(clamping: score.score))
        case .activityMinutes:
            return Format.duration(TimeInterval(score.score * 60))
        }
    }

    private func avatarSeed(for score: LeaderboardScore) -> String {
        score.avatarSeed ?? score.userHash ?? score.nickname
    }
}

private struct LeaderboardScoreRow: View {
    let score: LeaderboardScore
    let formattedScore: String
    let topScore: Int64
    let isCurrentUser: Bool

    private var fraction: Double {
        guard topScore > 0 else { return 0 }
        return min(max(Double(score.score) / Double(topScore), 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(score.rank ?? 0)")
                .font(.sora(11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isCurrentUser ? Color.stxAccent : Color.stxMuted)
                .frame(width: 44, alignment: .leading)
            BeamAvatarView(seed: score.avatarSeed ?? score.userHash ?? score.nickname, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(score.nickname)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isCurrentUser {
                        Text("YOU")
                            .font(.sora(8, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.stxAccent)
                    }
                }
                Text("Updated \(Format.relativeDate(score.updatedAt))")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            LeaderboardScoreBar(fraction: fraction, active: isCurrentUser)
                .frame(width: 130)

            Text(formattedScore)
                .font(.sora(13, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background {
            if isCurrentUser {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.stxAccent.opacity(0.08))
            }
        }
    }
}

private struct LeaderboardScoreBar: View {
    let fraction: Double
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(active ? Color.stxAccent : Color.primary.opacity(0.38))
                    .frame(width: max(4, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

private struct LeaderboardNotice: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private extension View {
    func segmentedBackground() -> some View {
        padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    func selectedSegment(_ isSelected: Bool) -> some View {
        background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.stxPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.stxStroke, lineWidth: 1)
                    )
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview {
    LeaderboardsView()
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 720)
        .background(Color.stxBackground)
}
#endif
