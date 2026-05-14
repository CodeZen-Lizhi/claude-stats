import SwiftUI

/// The Dashboard page: a Local heatmap (with a Commits / Claude-sessions
/// toggle), a GitHub contributions heatmap (when connected), and an Overlap
/// heatmap comparing the two. Persists toggle + range selection per scene
/// via `@SceneStorage`.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings

    @SceneStorage("dashboard.localSource") private var sourceRaw: String = DashboardViewModel.LocalSource.commits.rawValue
    @SceneStorage("dashboard.range") private var rangeRaw: String = DashboardViewModel.Range.last12Months.rawValue
    @SceneStorage("dashboard.onlyMyCommits") private var onlyMyCommits: Bool = true

    private var vm: DashboardViewModel { env.dashboard }

    private struct ReloadKey: Equatable {
        let source: DashboardViewModel.LocalSource
        let range: DashboardViewModel.Range
        let onlyMine: Bool
        let lastRefresh: Date?
        let provider: ProviderKind
        let githubEnabled: Bool
        let githubLogin: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                localPanel
                githubPanel
                if let overlap = vm.overlap {
                    overlapPanel(overlap: overlap)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { syncFromSceneStorage() }
        .onChange(of: vm.localSource) { _, new in sourceRaw = new.rawValue }
        .onChange(of: vm.range) { _, new in rangeRaw = new.rawValue }
        .onChange(of: vm.onlyMyCommits) { _, new in onlyMyCommits = new }
        .task(id: reloadKey) {
            let sessions = env.store.sessions(for: env.preferences.selectedProvider)
            await vm.reload(
                sessions: sessions,
                githubLogin: env.preferences.githubLogin,
                enableGitHub: env.preferences.githubEnabled
            )
            // If the fetch resolved a different login (rare — e.g. PAT now
            // points at a different user), keep prefs in sync.
            if case let .connected(login, _, _) = vm.githubStatus, login != env.preferences.githubLogin {
                env.preferences.githubLogin = login
            }
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            source: vm.localSource,
            range: vm.range,
            onlyMine: vm.onlyMyCommits,
            lastRefresh: env.store.lastRefreshedAt,
            provider: env.preferences.selectedProvider,
            githubEnabled: env.preferences.githubEnabled,
            githubLogin: env.preferences.githubLogin
        )
    }

    private func syncFromSceneStorage() {
        if let s = DashboardViewModel.LocalSource(rawValue: sourceRaw) { vm.localSource = s }
        if let r = DashboardViewModel.Range(rawValue: rangeRaw) { vm.range = r }
        vm.onlyMyCommits = onlyMyCommits
    }

    // MARK: - Header / controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DASHBOARD")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Coding activity")
                .font(.sora(24, weight: .semibold))
            Text("How often you ship code, day by day.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var controls: some View {
        @Bindable var bvm = vm
        return HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 8) {
                Text("RANGE")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                ForEach(DashboardViewModel.Range.allCases) { r in
                    DashboardChip(label: r.shortLabel, isSelected: vm.range == r) { vm.range = r }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text("LOCAL SOURCE")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                Menu {
                    ForEach(DashboardViewModel.LocalSource.allCases) { source in
                        Button(source.label) { vm.localSource = source }
                    }
                } label: {
                    BracketBox(spacing: 5) {
                        Label(vm.localSource.label, systemImage: "chevron.down")
                            .labelStyle(.titleAndIcon)
                            .font(.sora(11))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if vm.localSource == .commits {
                    Toggle(isOn: $bvm.onlyMyCommits) {
                        Text("Only my commits").font(.sora(11)).foregroundStyle(Color.stxMuted)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Local panel

    private var localPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOCAL")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                if vm.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(localSummaryText)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            if !vm.gitAvailable && vm.localSource == .commits {
                notice("GIT NOT AVAILABLE",
                       "Install the Xcode command-line tools to count commits.")
            } else if vm.cells.isEmpty && !vm.isLoading {
                notice("NO ACTIVITY", localEmptyHint)
            } else {
                HeatmapView(
                    cells: vm.cells,
                    range: vm.currentInterval(),
                    valueLabel: localHeatmapValueLabel
                )
            }
        }
        .stxPanel(16)
    }

    // MARK: - GitHub panel

    @ViewBuilder
    private var githubPanel: some View {
        if !env.preferences.githubEnabled {
            githubDisabledPanel
        } else {
            switch vm.githubStatus {
            case .disconnected:
                githubConnectCTA
            case .connecting:
                githubConnectingPanel
            case .connected(let login, let syncedAt, let isStale):
                githubConnectedPanel(login: login, syncedAt: syncedAt, isStale: isStale)
            case .failed(let reason):
                githubFailedPanel(reason: reason)
            }
        }
    }

    private var githubDisabledPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("Disabled")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            Text("Enable GitHub comparison in Settings to see your contribution graph alongside the local heatmap.")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            Button {
                openSettings()
            } label: {
                BracketBox(spacing: 5) {
                    Label("OPEN SETTINGS", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
        }
        .stxPanel(16)
    }

    private var githubConnectCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("Not connected")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(Color.stxAccent)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect a GitHub account to compare contribution patterns.")
                        .font(.sora(11))
                    Text("We only read your contribution counts — no code, issues, or PR data.")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Button {
                openSettings()
            } label: {
                BracketBox(spacing: 5) {
                    Label("CONNECT IN SETTINGS", systemImage: "key")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxAccent)
        }
        .stxPanel(16)
    }

    private var githubConnectingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                ProgressView().controlSize(.mini)
            }
            Text("Fetching contribution graph…")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .stxPanel(16)
    }

    private func githubConnectedPanel(login: String, syncedAt: Date?, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                HStack(spacing: 8) {
                    if isStale {
                        Text("STALE")
                            .font(.sora(9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.stxAccent)
                    }
                    Text("\(vm.githubTotalContributions) contributions · @\(login)")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                    if let syncedAt {
                        Text("· UPD \(Format.relativeDate(syncedAt))".uppercased())
                            .font(.sora(9))
                            .tracking(0.5)
                            .foregroundStyle(Color.stxMuted)
                    }
                    Button { Task { await vm.syncGitHubNow() } } label: {
                        BracketBox(spacing: 4) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxMuted)
                    .help("Sync now")
                }
            }
            if vm.githubCells.isEmpty {
                notice("NO CONTRIBUTIONS",
                       "GitHub returned zero contributions for this window. If you expected activity, check the token's scopes.")
            } else {
                HeatmapView(
                    cells: vm.githubCells,
                    range: vm.currentInterval(),
                    valueLabel: { value in value == 1 ? "1 contribution" : "\(value) contributions" }
                )
            }
        }
        .stxPanel(16)
    }

    private func githubFailedPanel(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxAccent)
                Spacer()
                Button { Task { await vm.syncGitHubNow() } } label: {
                    BracketBox(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Retry")
            }
            Text(reason)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            // Show stale cached cells if we have them.
            if !vm.githubCells.isEmpty {
                HeatmapView(
                    cells: vm.githubCells,
                    range: vm.currentInterval(),
                    valueLabel: { value in value == 1 ? "1 contribution" : "\(value) contributions" }
                )
            }
        }
        .stxPanel(16)
    }

    // MARK: - Overlap panel

    private func overlapPanel(overlap: OverlapStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("OVERLAP")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)

                Text("\(Format.percent(overlap.jaccard)) aligned")
                    .font(.sora(13, weight: .semibold))
                    .help(pearsonHelp(for: overlap))

                Spacer()
                Text(overlapBreakdown(overlap))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            OverlapHeatmapView(
                stats: overlap,
                range: vm.currentInterval(),
                palette: env.preferences.overlapPalette,
                valueLabel: overlapLabel
            )
        }
        .stxPanel(16)
    }

    private func overlapBreakdown(_ s: OverlapStats) -> String {
        "\(s.bothCount) both · \(s.localOnlyCount) local · \(s.githubOnlyCount) GitHub · \(s.neitherCount) neither"
    }

    private func pearsonHelp(for s: OverlapStats) -> String {
        guard let r = s.pearson else { return "Pearson correlation not defined (one series is constant)" }
        return String(format: "Pearson r = %.2f", r)
    }

    private func overlapLabel(_ state: OverlapStats.DayState) -> String {
        switch state {
        case .both: "Both local and GitHub activity"
        case .localOnly: "Local activity only"
        case .githubOnly: "GitHub activity only"
        case .neither: "No activity"
        }
    }

    // MARK: - Shared

    private func notice(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxAccent)
            Text(message)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var localSummaryText: String {
        switch vm.localSource {
        case .commits:
            return "\(vm.totalValue) commits · \(vm.activeDays) active days"
        case .sessions:
            return "\(Format.tokens(vm.totalValue)) tokens · \(vm.activeDays) active days"
        }
    }

    private var localEmptyHint: String {
        switch vm.localSource {
        case .commits:
            return "No commits in the selected window from the repos Claude has touched."
        case .sessions:
            return "No Claude sessions in the selected window for the current provider."
        }
    }

    private func localHeatmapValueLabel(_ value: Int) -> String {
        switch vm.localSource {
        case .commits: return value == 1 ? "1 commit" : "\(value) commits"
        case .sessions: return "\(Format.tokens(value)) tokens"
        }
    }
}

/// Same animated underline chip used elsewhere in the app (Activity / Git).
private struct DashboardChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label.uppercased())
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? .primary : (hovering ? Color.primary : Color.primary.opacity(0.40)))
                Rectangle()
                    .fill(Color.stxAccent)
                    .frame(height: 1.5)
                    .scaleEffect(x: isSelected ? 1 : 0, anchor: .center)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

#if DEBUG
#Preview("Dashboard") {
    DashboardView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
