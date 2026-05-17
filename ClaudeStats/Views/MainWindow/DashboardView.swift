import SwiftUI

/// Claude-style overview Dashboard: 8 stat cards (4×2) scoped by an
/// "All / 30d / 7d" range, then a side-by-side row with the 3-month Claude
/// heatmap on the left and the 3-month GitHub contributions heatmap on the
/// right, followed by the 3-month Claude↔GitHub overlap, and a humorous
/// comparison footer. The "Models" tab swaps the stat grid for a per-model
/// breakdown table.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings

    @SceneStorage("dashboard.section") private var sectionRaw: String = DashboardViewModel.Section.overview.rawValue
    @SceneStorage("dashboard.period") private var periodRaw: String = StatsPeriod.last30Days.rawValue

    /// GitHub cells filtered to the current heatmap window, cached so both
    /// `githubHeatmapSection` and `overlapCard` don't independently re-filter
    /// per body pass.
    @State private var githubCellsInRange: [HeatmapCell] = []
    /// Cached overlap stats. `nil` until inputs are available; recomputed via
    /// `refreshDerived()` when the inputs change. Saves two dict builds + two
    /// 90-day correlation walks per body pass.
    @State private var overlap: OverlapStats? = nil

    private var vm: DashboardViewModel { env.dashboard }

    private struct ReloadKey: Equatable {
        let period: StatsPeriod
        let provider: ProviderKind
        let lastRefresh: Date?
        let token: UInt64
        let githubEnabled: Bool
        let githubLogin: String
    }

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                Group {
                    switch vm.section {
                    case .overview: overviewBody
                    case .models: modelsBody
                    }
                }
                Spacer(minLength: 0)
            }
            // Horizontal padding trimmed (28 → 20) so the 4-column stat grid
            // fits inside the detail panel at the window's minimum width.
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            syncFromSceneStorage()
            refreshDerived()
        }
        .onChange(of: vm.section) { _, new in sectionRaw = new.rawValue }
        .onChange(of: vm.period) { _, new in periodRaw = new.rawValue }
        .onChange(of: vm.heatmapCells) { _, _ in refreshDerived() }
        .onChange(of: env.github.cells) { _, _ in refreshDerived() }
        .task(id: reloadKey) {
            let sessions = env.store.sessions(for: env.preferences.selectedProvider)
            await vm.reload(sessions: sessions)
            await env.github.reload(
                expectedLogin: env.preferences.githubLogin,
                enabled: env.preferences.githubEnabled
            )
            // If GitHub resolved a different login (rare — token now points
            // at a different user), keep prefs in sync.
            if case let .connected(login, _, _) = env.github.status,
               login != env.preferences.githubLogin {
                env.preferences.githubLogin = login
            }
            if env.preferences.selectedProvider == .claude {
                await env.claudeStatus.refreshIfNeeded()
            } else if env.preferences.selectedProvider == .codex {
                await env.openAIStatus.refreshIfNeeded()
            }
        }
    }

    private func refreshDerived() {
        let range = vm.heatmapInterval()
        let github = env.github.cells.filter { range.contains($0.date) }
        githubCellsInRange = github
        overlap = OverlapStats.compute(
            local: vm.heatmapCells,
            github: github,
            range: range
        )
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            period: vm.period,
            provider: env.preferences.selectedProvider,
            lastRefresh: env.store.lastRefreshedAt,
            token: vm.reloadToken,
            githubEnabled: env.preferences.githubEnabled,
            githubLogin: env.preferences.githubLogin
        )
    }

    private func syncFromSceneStorage() {
        if let s = DashboardViewModel.Section(rawValue: sectionRaw) { vm.section = s }
        if let p = StatsPeriod(rawValue: periodRaw),
           RangeChips.supported.contains(p) {
            vm.period = p
        }
    }

    // MARK: - Header & controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DASHBOARD")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Coding activity")
                .font(.sora(24, weight: .semibold))
            Text("Your Claude sessions, day by day.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var controls: some View {
        @Bindable var bvm = vm
        return HStack(alignment: .center, spacing: 12) {
            OverviewTabs(section: $bvm.section)
            Spacer()
            RangeChips(period: $bvm.period)
        }
    }

    // MARK: - Overview body

    private var overviewBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsGrid
            if env.preferences.selectedProvider == .claude {
                ClaudeStatusCard(status: env.claudeStatus)
            } else if env.preferences.selectedProvider == .codex {
                OpenAIStatusCard(status: env.openAIStatus)
            }
            heatmapsRow
            overlapSection
            ComparisonFooter(totalTokens: vm.stats.totalTokens)
        }
    }

    /// Eight stat cards in a 4×2 manual `Grid`. Hard-coded to four columns so
    /// the value baselines line up across both rows — `LazyVGrid` would
    /// reflow them and lose that alignment.
    private var statsGrid: some View {
        let s = vm.stats
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(label: "Sessions", value: "\(s.sessions)")
                StatCard(label: "Messages", value: Format.tokens(s.messages))
                StatCard(label: "Total tokens", value: Format.tokens(s.totalTokens))
                StatCard(label: "Active days", value: "\(s.activeDays)")
            }
            GridRow {
                StatCard(label: "Current streak", value: "\(s.currentStreak)d")
                StatCard(label: "Longest streak", value: "\(s.longestStreak)d")
                StatCard(label: "Peak hour", value: peakHourLabel(s.peakHour))
                StatCard(label: "Favorite model", value: favoriteModelLabel(s.favoriteModel))
            }
        }
    }

    // MARK: - Heatmap row (Claude + GitHub side-by-side, no card chrome)

    private var heatmapsRow: some View {
        HStack(alignment: .top, spacing: 32) {
            claudeHeatmapSection
            githubHeatmapSection
        }
        .padding(.top, 4)
    }

    private var claudeHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heatmapHeader(title: "CLAUDE ACTIVITY", subtitle: "\(vm.heatmapActiveDays) active days · last 3 months")
            CompactHeatmap(
                cells: vm.heatmapCells,
                range: vm.heatmapInterval(),
                valueLabel: { Format.tokens($0) + " tokens" }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var githubHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heatmapHeader(title: "GITHUB", subtitle: githubSubtitle)
            switch githubDisplay {
            case .placeholder(let message, let isCTA):
                githubPlaceholder(message: message, isCTA: isCTA)
            case .heatmap(let cells, _):
                CompactHeatmap(
                    cells: cells,
                    range: vm.heatmapInterval(),
                    valueLabel: { $0 == 1 ? "1 contribution" : "\($0) contributions" }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sora(9, weight: .medium)).tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Spacer()
            Text(subtitle)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    // MARK: - Overlap section

    @ViewBuilder
    private var overlapSection: some View {
        if env.preferences.githubEnabled,
           case .connected = env.github.status,
           !env.github.cells.isEmpty,
           let overlap {
            overlapCard(overlap: overlap)
        }
    }

    private func overlapCard(overlap: OverlapStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("OVERLAP")
                    .font(.sora(9, weight: .medium)).tracking(0.4)
                    .foregroundStyle(Color.stxMuted)
                Text("\(Format.percent(overlap.jaccard)) aligned")
                    .font(.sora(13, weight: .semibold))
                    .help(pearsonHelp(for: overlap))
                Spacer()
                Text(overlapBreakdown(overlap))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            OverlapHeatmapView(
                stats: overlap,
                range: vm.heatmapInterval(),
                palette: env.preferences.overlapPalette,
                valueLabel: overlapStateLabel
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    // MARK: - Models body

    private var modelsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelsTrendChart(
                series: vm.modelTrend,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: modelDisplayName
            )
            ModelTable(
                models: vm.modelBreakdown,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: modelDisplayName
            )
        }
    }

    /// Pretty label for a canonical model id, scoped to the active provider.
    private func modelDisplayName(_ id: String) -> String {
        env.store.displayName(forModel: id, provider: env.preferences.selectedProvider)
    }

    // MARK: - GitHub display state

    private enum GitHubDisplay {
        case placeholder(message: String, isCTA: Bool)
        case heatmap(cells: [HeatmapCell], totalInRange: Int)
    }

    private var githubDisplay: GitHubDisplay {
        guard env.preferences.githubEnabled else {
            return .placeholder(message: "Enable GitHub in Settings to compare your contributions.", isCTA: true)
        }
        switch env.github.status {
        case .disconnected:
            return .placeholder(message: "Connect a GitHub account in Settings to see your contribution graph.", isCTA: true)
        case .connecting:
            return .placeholder(message: "Fetching contribution graph…", isCTA: false)
        case .connected, .failed:
            let total = githubCellsInRange.reduce(0) { $0 + $1.value }
            return .heatmap(cells: githubCellsInRange, totalInRange: total)
        }
    }

    private var githubSubtitle: String {
        guard env.preferences.githubEnabled else { return "Disabled" }
        switch env.github.status {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected(let login, _, _):
            return "@\(login)"
        case .failed: return "Error"
        }
    }

    private func githubPlaceholder(message: String, isCTA: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            if isCTA {
                Button { openSettings() } label: {
                    BracketBox(spacing: 5) {
                        Label("OPEN SETTINGS", systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                            .font(.sora(10))
                            .tracking(0.8)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Overlap formatting helpers

    private func overlapBreakdown(_ s: OverlapStats) -> String {
        "\(s.bothCount) both · \(s.localOnlyCount) Claude · \(s.githubOnlyCount) GitHub · \(s.neitherCount) neither"
    }

    private func pearsonHelp(for s: OverlapStats) -> String {
        guard let r = s.pearson else { return "Pearson correlation not defined (one series is constant)" }
        return String(format: "Pearson r = %.2f", r)
    }

    private func overlapStateLabel(_ state: OverlapStats.DayState) -> String {
        switch state {
        case .both: "Both Claude and GitHub activity"
        case .localOnly: "Claude activity only"
        case .githubOnly: "GitHub activity only"
        case .neither: "No activity"
        }
    }

    // MARK: - Stat-card formatting helpers

    /// `"5 PM"` for hour 17 in the current locale. Returns "—" when no
    /// activity has been recorded yet.
    private func peakHourLabel(_ hour: Int?) -> String {
        guard let hour,
              let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)
        else { return "—" }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    /// Pretty display name for the favorite-model stat card. Goes through the
    /// provider so the format matches the Models tab (`Opus 4.7`, not
    /// `claude-opus-4-7` or `Opus-4-7`).
    private func favoriteModelLabel(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "—" }
        return modelDisplayName(model)
    }
}

#if DEBUG
#Preview("Dashboard") {
    DashboardView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
