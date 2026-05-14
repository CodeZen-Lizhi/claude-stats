import SwiftUI

/// The Dashboard page: a single Local heatmap (with a Commits / Claude-sessions
/// toggle) plus a placeholder card for the GitHub heatmap that arrives in a
/// later release. The page persists its toggle + range selection per scene via
/// `@SceneStorage` so reopening the window restores the previous view.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = DashboardViewModel()

    @SceneStorage("dashboard.localSource") private var sourceRaw: String = DashboardViewModel.LocalSource.commits.rawValue
    @SceneStorage("dashboard.range") private var rangeRaw: String = DashboardViewModel.Range.last12Months.rawValue
    @SceneStorage("dashboard.onlyMyCommits") private var onlyMyCommits: Bool = true

    private struct ReloadKey: Equatable {
        let source: DashboardViewModel.LocalSource
        let range: DashboardViewModel.Range
        let onlyMine: Bool
        let lastRefresh: Date?
        let provider: ProviderKind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                localPanel
                githubPanel
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
            await vm.reload(sessions: sessions)
        }
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            source: vm.localSource,
            range: vm.range,
            onlyMine: vm.onlyMyCommits,
            lastRefresh: env.store.lastRefreshedAt,
            provider: env.preferences.selectedProvider
        )
    }

    private func syncFromSceneStorage() {
        if let s = DashboardViewModel.LocalSource(rawValue: sourceRaw) { vm.localSource = s }
        if let r = DashboardViewModel.Range(rawValue: rangeRaw) { vm.range = r }
        vm.onlyMyCommits = onlyMyCommits
    }

    // MARK: - Sub-views

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
                    Text(summaryText)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            if !vm.gitAvailable && vm.localSource == .commits {
                notice("GIT NOT AVAILABLE",
                       "Install the Xcode command-line tools to count commits.")
            } else if vm.cells.isEmpty && !vm.isLoading {
                notice("NO ACTIVITY",
                       emptyHint)
            } else {
                HeatmapView(
                    cells: vm.cells,
                    range: vm.currentInterval(),
                    valueLabel: heatmapValueLabel
                )
            }
        }
        .stxPanel(16)
    }

    private var githubPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GITHUB")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("Coming soon")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.stxMuted)
                    .font(.system(size: 12))
                Text("Connect a GitHub account in a future update to compare your contributions against the activity above.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .stxPanel(16)
    }

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

    // MARK: - Derived display

    private var summaryText: String {
        switch vm.localSource {
        case .commits:
            return "\(vm.totalValue) commits · \(vm.activeDays) active days"
        case .sessions:
            return "\(Format.tokens(vm.totalValue)) tokens · \(vm.activeDays) active days"
        }
    }

    private var emptyHint: String {
        switch vm.localSource {
        case .commits:
            return "No commits in the selected window from the repos Claude has touched."
        case .sessions:
            return "No Claude sessions in the selected window for the current provider."
        }
    }

    private func heatmapValueLabel(_ value: Int) -> String {
        switch vm.localSource {
        case .commits: return value == 1 ? "1 commit" : "\(value) commits"
        case .sessions: return "\(Format.tokens(value)) tokens"
        }
    }
}

/// Same animated underline chip used elsewhere in the app (Activity / Git). Kept
/// private here so we don't reach into another view's nested type.
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
