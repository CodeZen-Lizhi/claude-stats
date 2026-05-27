import SwiftUI

struct GitRepoWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    let repoSelectionToken: UInt64
    @State private var vm: GitRepoGraphViewModel

    private static let rowHeight: CGFloat = 36
    private static let workingTreeRowHeight: CGFloat = 56
    private static let laneSpacing: CGFloat = 14
    private static let railPad: CGFloat = 18
    private static let nodeRadius: CGFloat = 3
    private static let graphInspectorSplitFraction: CGFloat = 0.63
    private static let graphMinWidth: CGFloat = 220
    private static let graphIdealWidth: CGFloat = 520
    private static let inspectorMinWidth: CGFloat = 290
    private static let inspectorIdealWidth: CGFloat = 300
    private static let inspectorMaxWidth: CGFloat = 360
    private static let historySplitFraction: CGFloat = 0.14
    private static let graphListMinHeight: CGFloat = 180
    private static let historyMinHeight: CGFloat = 72
    private static let historyMaxHeight: CGFloat = 150

    init(repo: GitRepo, repoSelectionToken: UInt64 = 0) {
        self.repo = repo
        self.repoSelectionToken = repoSelectionToken
        _vm = State(wrappedValue: GitRepoGraphViewModel())
    }

    #if DEBUG
    init(repo: GitRepo, previewGraph: GitGraph?, repoSelectionToken: UInt64 = 0) {
        self.repo = repo
        self.repoSelectionToken = repoSelectionToken
        if let previewGraph {
            _vm = State(wrappedValue: GitRepoGraphViewModel(previewGraph: previewGraph))
        } else {
            _vm = State(wrappedValue: GitRepoGraphViewModel())
        }
    }
    #endif

    private var railWidth: CGFloat {
        rowGeometry.railWidth(maxColumn: vm.layout?.maxColumn ?? 0)
    }

    private var rowGeometry: GitGraphRowGeometry {
        GitGraphRowGeometry(laneSpacing: Self.laneSpacing, railPad: Self.railPad)
    }

    var body: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: Self.graphInspectorSplitFraction,
            configuration: HoverableSplitViewConfiguration(
                primaryMinimumPaneLength: Self.graphMinWidth,
                secondaryMinimumPaneLength: Self.inspectorMinWidth,
                secondaryMaximumPaneLength: Self.inspectorMaxWidth
            )
        ) {
            graphColumn
                .frame(minWidth: Self.graphMinWidth, idealWidth: Self.graphIdealWidth, maxWidth: .infinity)
        } secondary: {
            GitCommitInspector(repo: repo, vm: vm)
                .frame(
                    minWidth: Self.inspectorMinWidth,
                    idealWidth: Self.inspectorIdealWidth,
                    maxWidth: Self.inspectorMaxWidth
                )
        }
        .task(id: "\(repo.id)|\(vm.limit)") {
            await vm.loadGraph(repo: repo)
        }
        .task(id: "\(repo.id)|\(vm.selectedHash ?? "")") {
            await vm.loadDetail(repo: repo)
        }
        .onChange(of: repo.id) { _, _ in
            vm.selectWorkingTree()
        }
        .onChange(of: repoSelectionToken) { _, _ in
            vm.selectWorkingTree()
        }
    }

    private var graphColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            graphHeader
            StxRule()
            graphContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var graphHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                FadingLineText(
                    repo.displayName,
                    font: .sora(18, weight: .semibold),
                    foregroundStyle: .primary,
                    fadeWidth: 42
                )
                FadingLineText(
                    repo.rootPath,
                    font: .sora(10),
                    foregroundStyle: Color.stxMuted,
                    fadeWidth: 42
                )
                    .help(repo.rootPath)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if vm.isGraphLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if let graph = vm.graph {
                Text(L10n.format("git.graph.commits_count", defaultValue: "%@ commits", "\(graph.commits.count)\(graph.truncated ? "+" : "")"))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if graph.workingTree.isDirty {
                    Text(L10n.format("git.graph.modified_count", defaultValue: "%@ modified", "\(graph.workingTree.fileCount)"))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                if graph.truncated {
                    Button {
                        vm.loadMore()
                    } label: {
                        Label(L10n.string("git.graph.more", defaultValue: "More"), systemImage: "plus")
                            .font(.sora(10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxAccent)
                    .help(L10n.string("git.graph.load_more", defaultValue: "Load more commits"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var graphContent: some View {
        if let graph = vm.graph, let layout = vm.layout, graph.workingTree.isDirty || !layout.rows.isEmpty {
            let hasWorkingTree = graph.workingTree.isDirty
            if let minimapData = vm.minimapData, !minimapData.buckets.isEmpty {
                HoverableSplitView(
                    axis: .horizontal,
                    primaryFraction: Self.historySplitFraction,
                    configuration: HoverableSplitViewConfiguration(
                        primaryMinimumPaneLength: Self.historyMinHeight,
                        primaryMaximumPaneLength: Self.historyMaxHeight,
                        secondaryMinimumPaneLength: Self.graphListMinHeight
                    )
                ) {
                    GitGraphMinimapView(
                        data: minimapData,
                        isLoading: vm.isMinimapLoading,
                        onTargetMaxBucketsChange: { targetMaxBuckets in
                            Task {
                                await vm.updateMinimapTargetMaxBuckets(targetMaxBuckets, repo: repo)
                            }
                        }
                    ) { bucket in
                        Task {
                            await vm.selectMinimapBucket(bucket, repo: repo)
                        }
                    }
                    .frame(minHeight: Self.historyMinHeight, maxHeight: .infinity)
                } secondary: {
                    graphRows(graph: graph, layout: layout, hasWorkingTree: hasWorkingTree)
                        .frame(minHeight: 0, maxHeight: .infinity)
                }
            } else {
                graphRows(graph: graph, layout: layout, hasWorkingTree: hasWorkingTree)
            }
        } else if vm.isGraphLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GitWorkspaceInlineEmptyState(L10n.string("git.graph.empty", defaultValue: "No commits to graph."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func graphRows(graph: GitGraph, layout: GraphLayout, hasWorkingTree: Bool) -> some View {
        AppScrollView {
            LazyVStack(spacing: 0) {
                if hasWorkingTree {
                    GitWorkingTreeRowView(
                        summary: graph.workingTree,
                        rowHeight: Self.workingTreeRowHeight,
                        geometry: rowGeometry,
                        nodeRadius: Self.nodeRadius,
                        railWidth: railWidth,
                        railColorIndex: layout.rows.first?.colorIndex ?? 0,
                        isSelected: false
                    ) {
                        vm.selectWorkingTree()
                    }
                }
                ForEach(layout.rows) { row in
                    GitGraphRowView(
                        row: row,
                        rowHeight: Self.rowHeight,
                        geometry: rowGeometry,
                        nodeRadius: Self.nodeRadius,
                        railWidth: railWidth,
                        isSelected: vm.selectedHash == row.commit.hash,
                        connectsFromTop: hasWorkingTree && row.id == layout.rows.first?.id
                    ) {
                        vm.selectCommit(row.commit.hash)
                    }
                }
            }
        }
    }
}

private struct GitCommitInspector: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    @Bindable var vm: GitRepoGraphViewModel

    @State private var diffRequest: GitFileDiffRequest?
    @State private var currentUserEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
            StxRule()
            commitBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppSurface.panelFill)
        .sheet(item: $diffRequest) { request in
            GitFileDiffViewer(request: request)
        }
        .task(id: repo.id) {
            currentUserEmail = await Task.detached(priority: .utility) {
                GitAnalyzer().currentUserEmail()
            }.value
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            FadingLineText(
                inspectorTitle,
                font: .sora(11, weight: .semibold),
                foregroundStyle: Color.stxMuted,
                tracking: 1.0,
                fadeWidth: 36
            )
            Spacer()
            if vm.isDetailLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var inspectorTitle: String {
        L10n.string("git.inspector.title", defaultValue: "COMMIT INSPECTOR")
    }

    @ViewBuilder
    private var commitBody: some View {
        if let commit = vm.selectedCommit {
            GeometryReader { proxy in
                let viewportWidth = max(0, proxy.size.width)

                AppScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        commitSummary(commit)
                        if let detail = vm.commitDetail {
                            commitMessage(detail)
                            changedFiles(detail)
                            commitUsage(commit)
                        } else if vm.isDetailLoading {
                            GitWorkspaceInlineEmptyState(L10n.string("git.inspector.loading_detail", defaultValue: "Loading commit detail."))
                        } else {
                            GitWorkspaceInlineEmptyState(L10n.string("git.inspector.detail_failed", defaultValue: "Couldn't load this commit."))
                        }
                    }
                    .padding(14)
                    .frame(width: viewportWidth, alignment: .topLeading)
                }
                .frame(width: viewportWidth, height: proxy.size.height, alignment: .topLeading)
            }
        } else {
            GitWorkspaceInlineEmptyState(L10n.string("git.inspector.select_commit", defaultValue: "Select a commit."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commitSummary(_ commit: GraphCommit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GitAvatar(name: commit.author, email: commit.authorEmail)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.author)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    Text(commit.authorEmail)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(TitleSanitizer.sanitize(commit.subject) ?? commit.subject)
                .font(.sora(13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxAccent)
                    .textSelection(.enabled)
                Text(Format.shortDate(commit.date))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if commit.isMerge {
                    Text(L10n.string("git.commit.merge", defaultValue: "merge"))
                        .font(.sora(9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }

            CommitBranchBadges(refs: vm.commitBranches)
        }
        .padding(12)
        .gitWorkspaceCard()
    }

    @ViewBuilder
    private func commitMessage(_ detail: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("git.commit.message", defaultValue: "MESSAGE"))
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if detail.body.isEmpty {
                Text(L10n.string("git.commit.no_body", defaultValue: "No commit body."))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            } else {
                Text(detail.body)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .gitWorkspaceCard()
    }

    private func changedFiles(_ detail: CommitDetail) -> some View {
        GitChangedFilesPanel(
            summary: "+\(detail.totalInsertions) -\(detail.totalDeletions)",
            emptyMessage: detail.isMerge
                ? L10n.string("git.changed_files.merge_empty", defaultValue: "Merge commit with no file diff.")
                : L10n.string("git.changed_files.empty", defaultValue: "No file changes."),
            rows: detail.files.map(GitChangedFileRowModel.init(commitFile:))
        ) { row in
            guard let path = row.openPath else { return }
            diffRequest = GitFileDiffRequest(
                repo: repo,
                hash: detail.hash,
                parentHash: detail.parentHashes.first,
                abbreviatedHash: detail.abbreviatedHash,
                path: path
            )
        }
    }

    private func commitUsage(_ commit: GraphCommit) -> some View {
        let attribution = CommitUsageAttribution.make(
            commit: commit,
            graph: vm.graph,
            sessions: env.store.gitAttributionSessions.filter { $0.provider == env.preferences.selectedProvider },
            repo: repo,
            currentUserEmail: currentUserEmail
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("git.commit.ai_usage", defaultValue: "AI USAGE"))
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text(attribution.windowLabel)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if attribution.isEligible {
                ViewThatFits(in: .horizontal) {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            usageMetric(L10n.string("usage.stat.requests", defaultValue: "REQUESTS"), Format.tokens(attribution.requestCount))
                            usageMetric(L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), Format.tokens(attribution.usage.total(includingCacheRead: env.preferences.includeCacheInTokens)))
                        }
                        GridRow {
                            usageMetric(L10n.string("usage.stat.input", defaultValue: "INPUT"), Format.tokens(attribution.usage.inputTokens))
                            usageMetric(L10n.string("usage.stat.output", defaultValue: "OUTPUT"), Format.tokens(attribution.usage.outputTokens))
                        }
                        GridRow {
                            usageMetric(L10n.string("usage.stat.cached", defaultValue: "CACHED"), Format.tokens(attribution.usage.cacheReadTokens))
                            usageMetric(L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), Format.cost(attribution.cost))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        usageMetric(L10n.string("usage.stat.requests", defaultValue: "REQUESTS"), Format.tokens(attribution.requestCount))
                        usageMetric(L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), Format.tokens(attribution.usage.total(includingCacheRead: env.preferences.includeCacheInTokens)))
                        usageMetric(L10n.string("usage.stat.input", defaultValue: "INPUT"), Format.tokens(attribution.usage.inputTokens))
                        usageMetric(L10n.string("usage.stat.output", defaultValue: "OUTPUT"), Format.tokens(attribution.usage.outputTokens))
                        usageMetric(L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), Format.cost(attribution.cost))
                    }
                }

                if attribution.models.isEmpty {
                    GitWorkspaceInlineEmptyState(L10n.string("git.commit.ai_usage.empty", defaultValue: "No billable AI requests found in this commit window."))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(attribution.models) { model in
                            HStack(spacing: 8) {
                                Text(model.name)
                                    .font(.sora(10, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(Format.tokens(model.usage.total(includingCacheRead: env.preferences.includeCacheInTokens)))
                                    .font(.sora(10).monospacedDigit())
                                    .foregroundStyle(Color.stxMuted)
                            }
                        }
                    }
                }
            } else {
                GitWorkspaceInlineEmptyState(attribution.ineligibleMessage)
            }
        }
        .padding(12)
        .gitWorkspaceCard()
    }

    private func usageMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.sora(8, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(14, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

}

private struct CommitUsageAttribution {
    struct Model: Identifiable {
        let name: String
        let usage: TokenUsage
        let cost: CostEstimate

        var id: String { name }
    }

    let isEligible: Bool
    let ineligibleMessage: String
    let requestCount: Int
    let usage: TokenUsage
    let cost: Double
    let models: [Model]
    let windowLabel: String

    static func make(
        commit: GraphCommit,
        graph: GitGraph?,
        sessions: [Session],
        repo: GitRepo,
        currentUserEmail: String?
    ) -> CommitUsageAttribution {
        guard let currentUserEmail, !currentUserEmail.isEmpty else {
            return CommitUsageAttribution(
                isEligible: false,
                ineligibleMessage: L10n.string("git.commit.ai_usage.no_email", defaultValue: "Set git user.email to attribute AI usage to your commits."),
                requestCount: 0,
                usage: .zero,
                cost: 0,
                models: [],
                windowLabel: L10n.string("git.commit.ai_usage.my_commits_only", defaultValue: "my commits only")
            )
        }
        guard commit.authorEmail.caseInsensitiveCompare(currentUserEmail) == .orderedSame else {
            return CommitUsageAttribution(
                isEligible: false,
                ineligibleMessage: L10n.format(
                    "git.commit.ai_usage.not_mine",
                    defaultValue: "AI usage is attributed only to commits authored by %@.",
                    currentUserEmail
                ),
                requestCount: 0,
                usage: .zero,
                cost: 0,
                models: [],
                windowLabel: L10n.string("git.commit.ai_usage.my_commits_only", defaultValue: "my commits only")
            )
        }

        let previousDate = previousCommitDate(for: commit, in: graph, email: currentUserEmail)
        let lowerLabel = previousDate.map { Format.shortDate($0) } ?? L10n.string("git.commit.ai_usage.repo_start", defaultValue: "repo start")
        let windowLabel = "\(lowerLabel) -> \(Format.shortDate(commit.date))"
        var perModel: [String: (requests: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var seenHashes = Set<String>()

        for session in sessions where belongsToRepo(session, repo: repo) {
            guard let stats = session.stats else { continue }
            if stats.billableMessages.isEmpty {
                let activity = stats.lastActivity ?? session.lastModified
                guard contains(activity, lowerBound: previousDate, upperBound: commit.date) else { continue }
                for model in stats.models {
                    var acc = perModel[model.model] ?? (0, .zero, .zero)
                    acc.requests += model.messageCount
                    acc.usage += model.usage
                    acc.cost += model.costEstimate
                    perModel[model.model] = acc
                }
            } else {
                for bill in stats.billableMessages {
                    guard let timestamp = bill.timestamp,
                          contains(timestamp, lowerBound: previousDate, upperBound: commit.date) else { continue }
                    if let hash = bill.hash {
                        guard seenHashes.insert(hash).inserted else { continue }
                    }
                    var acc = perModel[bill.model] ?? (0, .zero, .zero)
                    acc.requests += 1
                    acc.usage += bill.usage
                    acc.cost += bill.cost
                    perModel[bill.model] = acc
                }
            }
        }

        let models = perModel.map { model, value in
            Model(name: model, usage: value.usage, cost: value.cost)
        }
        .sorted { lhs, rhs in
            if lhs.usage.total != rhs.usage.total { return lhs.usage.total > rhs.usage.total }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return CommitUsageAttribution(
            isEligible: true,
            ineligibleMessage: "",
            requestCount: perModel.values.reduce(0) { $0 + $1.requests },
            usage: perModel.values.reduce(.zero) { $0 + $1.usage },
            cost: perModel.values.reduce(0) { $0 + $1.cost.standardAPI },
            models: models,
            windowLabel: windowLabel
        )
    }

    private static func previousCommitDate(for commit: GraphCommit, in graph: GitGraph?, email: String) -> Date? {
        guard let commits = graph?.commits else { return nil }
        return commits
            .filter { $0.hash != commit.hash && $0.authorEmail.caseInsensitiveCompare(email) == .orderedSame && $0.date < commit.date }
            .map(\.date)
            .max()
    }

    private static func belongsToRepo(_ session: Session, repo: GitRepo) -> Bool {
        guard let cwd = session.cwd, !cwd.isEmpty else { return false }
        return cwd == repo.rootPath || cwd.hasPrefix(repo.rootPath + "/")
    }

    private static func contains(_ date: Date, lowerBound: Date?, upperBound: Date) -> Bool {
        if let lowerBound, date <= lowerBound { return false }
        return date <= upperBound
    }
}

private struct CommitBranchBadges: View {
    private let visibleLimit = 2

    let refs: [GitRef]
    @State private var showingMore = false

    private var visibleRefs: [GitRef] {
        Array(refs.prefix(visibleLimit))
    }

    private var hiddenRefs: [GitRef] {
        Array(refs.dropFirst(visibleLimit))
    }

    var body: some View {
        if refs.isEmpty {
            Text(L10n.string("git.commit.branches.none", defaultValue: "No containing branch found."))
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(visibleRefs.enumerated()), id: \.offset) { _, ref in
                    GitRefPill(ref: ref)
                }
                if !hiddenRefs.isEmpty {
                    Button {
                        showingMore = true
                    } label: {
                        AppBadge("+\(hiddenRefs.count)", tone: .muted)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingMore, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("git.commit.branches.more", defaultValue: "Containing branches"))
                                .font(.sora(11, weight: .semibold))
                            ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                                GitRefPill(ref: ref)
                            }
                        }
                        .padding(12)
                        .frame(minWidth: 180, alignment: .leading)
                    }
                    .help(L10n.string("git.commit.branches.show_all", defaultValue: "Show all containing branches"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GitWorkspaceInlineEmptyState: View {
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
    func gitWorkspaceCard() -> some View {
        appSurface(.compactCard(radius: 10))
    }
}

#if DEBUG
#Preview("Repo workspace") {
    GitRepoWorkspaceView(repo: GitGraph.preview().repo, previewGraph: .preview())
        .environment(AppEnvironment.preview())
        .frame(width: 760, height: 560)
        .background(Color.stxBackground)
}
#endif
