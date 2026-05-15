import SwiftUI
import Charts

/// Main-window Git surface. Unlike the compact menu-bar pane, this view is a
/// repository-oriented workspace with stable selection and a denser desktop
/// layout.
struct MainGitActivityView: View {
    @Environment(AppEnvironment.self) private var env
    @SceneStorage("mainWindow.gitSelection") private var selectionRaw: String = Self.allSelection
    @State private var vm: GitActivityViewModel
    @State private var previewSelectionRaw: String?

    private let isPreview: Bool
    #if DEBUG
    private let previewGraph: GitGraph?
    #endif

    private static let allSelection = "all"

    init() {
        _vm = State(wrappedValue: GitActivityViewModel())
        _previewSelectionRaw = State(wrappedValue: nil)
        isPreview = false
        #if DEBUG
        previewGraph = nil
        #endif
    }

    #if DEBUG
    init(previewModel: GitActivityViewModel, selection: String = Self.allSelection, graph: GitGraph? = nil) {
        _vm = State(wrappedValue: previewModel)
        _previewSelectionRaw = State(wrappedValue: selection)
        isPreview = true
        previewGraph = graph
    }
    #endif

    private struct ReloadKey: Equatable {
        let token: UInt64
        let lastRefreshed: Date?
        let provider: ProviderKind
    }

    private var currentSelection: String {
        previewSelectionRaw ?? selectionRaw
    }

    private var selectedActivity: RepoActivity? {
        guard currentSelection != Self.allSelection else { return nil }
        return vm.repos.first { $0.repo.id == currentSelection }
    }

    var body: some View {
        @Bindable var vm = vm
        let provider = env.preferences.selectedProvider
        let key = ReloadKey(token: vm.reloadToken, lastRefreshed: env.store.lastRefreshedAt, provider: provider)

        return VStack(spacing: 0) {
            header(model: vm)
            StxRule()
            HStack(spacing: 0) {
                GitRepoSelectionColumn(
                    repos: vm.repos,
                    totalCommits: vm.totalCommits,
                    totalChurn: vm.totalInsertions + vm.totalDeletions,
                    selection: currentSelection,
                    isLoading: vm.isLoading,
                    onSelect: setSelection
                )
                .frame(width: 196)

                Rectangle()
                    .fill(Color.stxStroke)
                    .frame(width: 1)

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: key) {
            if isPreview { return }
            await vm.reload(sessions: env.store.sessions(for: provider))
            reconcileSelection()
        }
        .onAppear { reconcileSelection() }
        .onChange(of: vm.repos.map(\.id)) { _, _ in reconcileSelection() }
    }

    private func header(model: GitActivityViewModel) -> some View {
        @Bindable var vm = model
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIT ACTIVITY")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text("Repository workspace")
                    .font(.sora(24, weight: .semibold))
                    .lineLimit(1)
                Text("Commits from projects where Claude sessions ran.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading git activity")
            }
            MainGitMineToggle(onlyMyCommits: $vm.onlyMyCommits, userEmail: vm.userEmail)
            MainGitRangePicker(range: $vm.range)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var detailContent: some View {
        if !vm.gitAvailable {
            GitWorkspaceNotice(
                title: "Git not available",
                message: "Couldn't run the git command. Install the Xcode command-line tools and refresh."
            )
        } else if !vm.hasData {
            GitWorkspaceNotice(
                title: "No git activity",
                message: "No Claude-used projects have git commits in this range. Try a wider window or disable My Commits."
            )
        } else if let activity = selectedActivity {
            #if DEBUG
            GitRepoWorkspaceView(repo: activity.repo, previewGraph: previewGraph)
            #else
            GitRepoWorkspaceView(repo: activity.repo)
            #endif
        } else {
            GitOverviewContent(
                repos: vm.repos,
                points: vm.correlationPoints,
                recentCommits: vm.recentCommits(),
                totalCommits: vm.totalCommits,
                totalInsertions: vm.totalInsertions,
                totalDeletions: vm.totalDeletions,
                totalFilesChanged: vm.totalFilesChanged
            )
        }
    }

    private func setSelection(_ value: String) {
        if isPreview {
            previewSelectionRaw = value
        } else {
            selectionRaw = value
        }
    }

    private func reconcileSelection() {
        guard currentSelection != Self.allSelection else { return }
        if !vm.repos.contains(where: { $0.repo.id == currentSelection }) {
            setSelection(Self.allSelection)
        }
    }
}

private struct GitRepoSelectionColumn: View {
    let repos: [RepoActivity]
    let totalCommits: Int
    let totalChurn: Int
    let selection: String
    let isLoading: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
            FadingScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    GitRepoSelectionRow(
                        title: "All Repos",
                        subtitle: "\(totalCommits) commits",
                        detail: Format.tokens(totalChurn) + " churn",
                        symbol: "square.grid.2x2",
                        isSelected: selection == "all"
                    ) {
                        onSelect("all")
                    }

                    ForEach(repos) { activity in
                        GitRepoSelectionRow(
                            title: activity.repo.displayName,
                            subtitle: "\(activity.commitCount) commits",
                            detail: "\(activity.filesChanged) files",
                            symbol: "folder",
                            isSelected: selection == activity.repo.id
                        ) {
                            onSelect(activity.repo.id)
                        }
                        .help(activity.repo.rootPath)
                    }
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Text("REPOSITORIES")
                .font(.sora(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct GitRepoSelectionRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sora(11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text(subtitle)
                        Text("-")
                        Text(detail)
                    }
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.stxStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(title))
    }

    private var rowBackground: Color {
        if isSelected { return Color.stxPanel }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

private struct GitOverviewContent: View {
    let repos: [RepoActivity]
    let points: [GitActivityViewModel.CorrelationPoint]
    let recentCommits: [GitCommit]
    let totalCommits: Int
    let totalInsertions: Int
    let totalDeletions: Int
    let totalFilesChanged: Int

    private var repoNamesByID: [String: String] {
        Dictionary(repos.map { ($0.repo.id, $0.repo.displayName) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metricsGrid
                GitCorrelationPanel(points: points)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        GitChurnTable(repos: repos)
                            .frame(minWidth: 260, maxWidth: .infinity)
                        GitRecentCommitsTable(commits: recentCommits, repoNamesByID: repoNamesByID)
                            .frame(minWidth: 320, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        GitChurnTable(repos: repos)
                        GitRecentCommitsTable(commits: recentCommits, repoNamesByID: repoNamesByID)
                    }
                }
            }
            .padding(20)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            StatCard(label: "Repos", value: "\(repos.count)")
            StatCard(label: "Commits", value: "\(totalCommits)")
            StatCard(label: "Lines +/-", value: "\(Format.tokens(totalInsertions))/\(Format.tokens(totalDeletions))")
            StatCard(label: "Files touched", value: "\(totalFilesChanged)")
        }
    }
}

private struct GitCorrelationPanel: View {
    let points: [GitActivityViewModel.CorrelationPoint]

    private var hasTokens: Bool { points.contains { $0.claudeTokens > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLAUDE USAGE VS COMMITS")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("\(points.reduce(0) { $0 + $1.commitCount }) commits")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            if points.isEmpty {
                GitInlineEmptyState("Nothing to plot for this range.")
            } else {
                Text("CLAUDE TOKENS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                tokensChart
                Text("COMMITS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                commitsChart
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private var tokensChart: some View {
        Chart(points) { point in
            AreaMark(x: .value("When", point.start), y: .value("Tokens", point.claudeTokens))
                .foregroundStyle(Color.stxAccent.opacity(0.16))
                .interpolationMethod(.monotone)
            LineMark(x: .value("When", point.start), y: .value("Tokens", point.claudeTokens))
                .foregroundStyle(Color.stxAccent)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(Format.tokens(v))
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXScale(domain: chartDomain(points.map(\.start)))
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: hasTokens ? 96 : 44)
        .opacity(hasTokens ? 1 : 0.5)
    }

    private var commitsChart: some View {
        Chart(points) { point in
            BarMark(x: .value("When", point.start), y: .value("Commits", point.commitCount))
                .foregroundStyle(Color.primary.opacity(0.55))
                .cornerRadius(1)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartXScale(domain: chartDomain(points.map(\.start)))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.sora(8))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 96)
    }

    private func chartDomain(_ starts: [Date]) -> ClosedRange<Date> {
        guard let first = starts.first, let last = starts.last else {
            let now = Date.now
            return now ... now.addingTimeInterval(1)
        }
        let step = starts.count >= 2 ? starts[1].timeIntervalSince(starts[0]) : 86_400
        return first.addingTimeInterval(-step / 2) ... last.addingTimeInterval(step / 2)
    }
}

private struct GitChurnTable: View {
    let repos: [RepoActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitTableTitle(title: "CODE CHURN BY REPO", detail: "\(repos.count) repos")
            StxRule()
            ForEach(repos) { activity in
                HStack(spacing: 8) {
                    Text(activity.repo.displayName)
                        .font(.sora(11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("+\(Format.tokens(activity.insertions))")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(GitPalette.add)
                    Text("-\(Format.tokens(activity.deletions))")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(GitPalette.del)
                    Text("\(activity.filesChanged) files")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if activity.id != repos.last?.id { StxRule() }
            }
        }
        .gitMainCard()
    }
}

private struct GitRecentCommitsTable: View {
    let commits: [GitCommit]
    let repoNamesByID: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitTableTitle(title: "RECENT COMMITS", detail: "\(commits.count) shown")
            StxRule()
            if commits.isEmpty {
                GitInlineEmptyState("No commits in this range.")
                    .padding(14)
            } else {
                ForEach(commits) { commit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TitleSanitizer.sanitize(commit.subject) ?? commit.subject)
                            .font(.sora(11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 6) {
                            Text(repoNamesByID[commit.repoID] ?? "-")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(commit.shortHash)
                            Text("+\(commit.insertions) -\(commit.deletions)")
                            Spacer(minLength: 6)
                            Text(Format.relativeDate(commit.date))
                        }
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if commit.id != commits.last?.id { StxRule() }
                }
            }
        }
        .gitMainCard()
    }
}

private struct GitTableTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sora(12, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text(detail)
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .padding(12)
    }
}

private struct MainGitRangePicker: View {
    @Binding var range: GitRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GitRange.allCases) { value in
                chip(value)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .help("Select git activity range")
    }

    private func chip(_ value: GitRange) -> some View {
        let isSelected = range == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { range = value }
        } label: {
            Text(value.shortLabel.lowercased())
                .font(.sora(11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.stxPanel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.stxStroke, lineWidth: 1)
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MainGitMineToggle: View {
    @Binding var onlyMyCommits: Bool
    let userEmail: String?

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { onlyMyCommits.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: onlyMyCommits ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(onlyMyCommits ? Color.stxAccent : Color.stxMuted)
                Text("My Commits")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(userEmail.map { "Only count commits authored by \($0)" } ?? "Only count commits by your git user.email")
    }
}

private struct GitWorkspaceNotice: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sora(18, weight: .semibold))
            Text(message)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .gitMainCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct GitInlineEmptyState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}

private extension View {
    func gitMainCard() -> some View {
        self
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

#if DEBUG
#Preview("Main Git - all repos") {
    MainGitActivityView(previewModel: .preview())
        .environment(AppEnvironment.preview())
        .frame(width: 800, height: 620)
        .background(Color.stxBackground)
}

#Preview("Main Git - repo") {
    let previewModel = GitActivityViewModel.preview()
    return MainGitActivityView(
        previewModel: previewModel,
        selection: GitGraph.preview().repo.id,
        graph: .preview()
    )
    .environment(AppEnvironment.preview())
    .frame(width: 900, height: 620)
    .background(Color.stxBackground)
}

#Preview("Main Git - empty") {
    MainGitActivityView(previewModel: .previewEmpty())
        .environment(AppEnvironment.preview(populated: false))
        .frame(width: 800, height: 620)
        .background(Color.stxBackground)
}
#endif
