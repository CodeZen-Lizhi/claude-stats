import SwiftUI

struct LeaderboardsView: View {
    @Environment(AppEnvironment.self) private var env

    @SceneStorage("mainWindow.leaderboards.metric") private var metricRaw: String = LeaderboardMetric.tokensWithCache.rawValue
    @SceneStorage("mainWindow.leaderboards.period") private var periodRaw: String = LeaderboardPeriod.day.rawValue
    @SceneStorage("mainWindow.leaderboards.selectedUserHash") private var selectedUserHashRaw: String = ""

    @State private var metric: LeaderboardMetric = .tokensWithCache
    @State private var period: LeaderboardPeriod = .day
    @State private var selectedScoreIDOverride: String?

    private var reloadID: String {
        "\(metric.rawValue)-\(period.rawValue)-\(env.preferences.leaderboardsEnabled)"
    }

    private var historyReloadID: String {
        [
            selectedScore?.id ?? "none",
            selectedScore?.userHash ?? "no-user-hash",
            metric.rawValue,
            period.rawValue,
            anchorWindow.periodKey,
            "\(env.preferences.leaderboardsEnabled)",
        ].joined(separator: "|")
    }

    private var scores: [LeaderboardScore] {
        env.leaderboards.scores
    }

    private var topScore: Int64 {
        scores.first?.score ?? 0
    }

    private var selectedUserHash: String? {
        selectedUserHashRaw.isEmpty ? nil : selectedUserHashRaw
    }

    private var selectedScore: LeaderboardScore? {
        if let selectedScoreIDOverride,
           let score = scores.first(where: { $0.id == selectedScoreIDOverride }) {
            return score
        }
        return LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: selectedUserHash,
            currentUserHash: env.leaderboards.currentUserHash,
            scores: scores
        )
    }

    private var anchorWindow: LeaderboardPeriodWindow {
        if let periodKey = env.leaderboards.lastLoadedPeriodKey,
           let window = LeaderboardPeriodCalculator.window(for: period, periodKey: periodKey) {
            return window
        }
        return LeaderboardPeriodCalculator.window(for: period)
    }

    private var isSyncBusy: Bool {
        env.leaderboards.syncStatus == .syncing
            || env.leaderboards.syncStatus == .checkingAccount
            || env.leaderboards.isSavingProfile
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = LeaderboardLayout.contentWidth(for: proxy.size.width)
            let isWide = contentWidth >= LeaderboardLayout.wideMinimumWidth

            FadingScrollView {
                layout(contentWidth: contentWidth, isWide: isWide)
                    .frame(width: contentWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LeaderboardLayout.horizontalPadding)
                    .padding(.top, LeaderboardLayout.topPadding)
                    .padding(.bottom, LeaderboardLayout.bottomPadding)
            }
        }
        .onAppear {
            syncFromSceneStorage()
            reconcileSelection()
        }
        .task(id: reloadID) {
            guard env.preferences.leaderboardsEnabled else { return }
            await env.leaderboards.loadScores(metric: metric, period: period)
        }
        .onChange(of: metric) { _, new in
            metricRaw = new.rawValue
            reconcileSelection()
        }
        .onChange(of: period) { _, new in
            periodRaw = new.rawValue
            reconcileSelection()
        }
        .onChange(of: env.leaderboards.scores) { _, _ in
            reconcileSelection()
        }
        .onChange(of: env.leaderboards.currentUserHash) { _, _ in
            reconcileSelection()
        }
    }

    @ViewBuilder
    private func layout(contentWidth: CGFloat, isWide: Bool) -> some View {
        if isWide {
            LeaderboardWideWorkspaceLayout(
                leftWidth: LeaderboardLayout.leftColumnWidth,
                detailMinWidth: LeaderboardLayout.detailMinWidth,
                columnSpacing: LeaderboardLayout.columnSpacing,
                headerSpacing: LeaderboardLayout.headerContentSpacing
            ) {
                titleHeader
                    .frame(width: LeaderboardLayout.leftColumnWidth, alignment: .topLeading)

                listColumn
                    .frame(width: LeaderboardLayout.leftColumnWidth, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                detailColumn
                    .frame(minWidth: LeaderboardLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: contentWidth, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: LeaderboardLayout.headerContentSpacing) {
                titleHeader
                if env.preferences.leaderboardsEnabled {
                    overviewPanel
                }
                listColumn
            }
                .frame(width: contentWidth, alignment: .top)
        }
    }

    private var titleHeader: some View {
        LeaderboardTitleHeader()
    }

    private var overviewPanel: some View {
        LeaderboardOverviewPanel(
            metric: $metric,
            period: $period,
            scores: scores,
            topScore: topScore,
            currentUserHash: env.leaderboards.currentUserHash,
            syncStatusText: env.leaderboards.syncStatus.displayText,
            isLoadingScores: env.leaderboards.isLoadingScores,
            isSyncBusy: isSyncBusy,
            onRefresh: {
                Task { await env.leaderboards.loadScores(metric: metric, period: period) }
            },
            onSync: {
                Task {
                    await env.leaderboards.syncNow()
                    await env.leaderboards.loadScores(metric: metric, period: period)
                }
            }
        )
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if env.preferences.leaderboardsEnabled {
                overviewPanel
            }
            LeaderboardDetailPanel(
                score: selectedScore,
                scores: scores,
                metric: metric,
                period: period,
                topScore: topScore,
                currentUserScore: env.leaderboards.currentUserScore,
                currentUserHash: env.leaderboards.currentUserHash,
                history: env.leaderboards.selectedUserHistory,
                isLoadingHistory: env.leaderboards.isLoadingSelectedUserHistory,
                historyError: env.leaderboards.selectedUserHistoryError
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: historyReloadID) {
            await loadSelectedUserHistoryIfNeeded()
        }
    }

    private var listColumn: some View {
        LeaderboardListColumn(
            metric: metric,
            scores: scores,
            topScore: topScore,
            selectedScoreID: selectedScore?.id,
            currentUserHash: env.leaderboards.currentUserHash,
            isLoadingScores: env.leaderboards.isLoadingScores,
            scoreError: env.leaderboards.scoreError,
            scoreEmptyMessage: env.leaderboards.scoreEmptyMessage,
            lastLoadedPeriodKey: env.leaderboards.lastLoadedPeriodKey,
            leaderboardsEnabled: env.preferences.leaderboardsEnabled,
            onSelectScore: selectScore,
            onOpenSettings: {
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
            }
        )
    }

    private func syncFromSceneStorage() {
        metric = LeaderboardMetric(rawValue: metricRaw) ?? .tokensWithCache
        period = LeaderboardPeriod(rawValue: periodRaw) ?? .day
    }

    private func selectScore(_ score: LeaderboardScore) {
        selectedScoreIDOverride = score.id
        selectedUserHashRaw = score.userHash ?? ""
    }

    private func reconcileSelection() {
        if let selectedScoreIDOverride,
           scores.contains(where: { $0.id == selectedScoreIDOverride }) {
            return
        }
        selectedScoreIDOverride = nil
        let score = LeaderboardSelectionResolver.selectedScore(
            preferredUserHash: selectedUserHash,
            currentUserHash: env.leaderboards.currentUserHash,
            scores: scores
        )
        selectedUserHashRaw = score?.userHash ?? ""
    }

    private func loadSelectedUserHistoryIfNeeded() async {
        guard env.preferences.leaderboardsEnabled,
              let score = selectedScore,
              let userHash = score.userHash else {
            env.leaderboards.clearSelectedUserHistory()
            return
        }
        await env.leaderboards.loadScoreHistory(
            userHash: userHash,
            metric: metric,
            period: period
        )
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
