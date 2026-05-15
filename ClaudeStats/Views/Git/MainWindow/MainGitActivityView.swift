import SwiftUI

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
                    totalCommits: vm.overviewSnapshot.totalCommits,
                    totalChurn: vm.overviewSnapshot.totalChurn,
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
            GitOverviewContent(snapshot: vm.overviewSnapshot)
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
            FadingScrollView(chrome: .plain) {
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

private enum GitOverviewTableLayout: Equatable {
    case wide
    case narrow

    static func forWidth(_ width: CGFloat) -> Self {
        width >= 680 ? .wide : .narrow
    }
}

private struct GitOverviewContent: View {
    let snapshot: GitActivityViewModel.OverviewSnapshot

    @State private var tableLayout: GitOverviewTableLayout = .wide

    var body: some View {
        FadingScrollView(chrome: .plain) {
            VStack(alignment: .leading, spacing: 16) {
                metricsGrid
                GitCorrelationPanel(correlation: snapshot.correlation)
                tables
            }
            .padding(20)
            .onGeometryChange(for: GitOverviewTableLayout.self) { proxy in
                GitOverviewTableLayout.forWidth(proxy.size.width)
            } action: { newLayout in
                if tableLayout != newLayout {
                    tableLayout = newLayout
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(snapshot.stats) { stat in
                StatCard(label: stat.label, value: stat.value)
            }
        }
    }

    @ViewBuilder
    private var tables: some View {
        switch tableLayout {
        case .wide:
            HStack(alignment: .top, spacing: 16) {
                GitChurnTable(rows: snapshot.churnRows, detail: snapshot.churnRowsDetail)
                    .frame(minWidth: 260, maxWidth: .infinity)
                GitRecentCommitsTable(rows: snapshot.recentRows)
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
        case .narrow:
            VStack(alignment: .leading, spacing: 16) {
                GitChurnTable(rows: snapshot.churnRows, detail: snapshot.churnRowsDetail)
                GitRecentCommitsTable(rows: snapshot.recentRows)
            }
        }
    }
}

private struct GitCorrelationPanel: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLAUDE USAGE VS COMMITS")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(correlation.commitCountLabel)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            if correlation.points.isEmpty {
                GitInlineEmptyState("Nothing to plot for this range.")
            } else {
                Text("CLAUDE TOKENS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                GitTokenOverviewChart(correlation: correlation)
                Text("COMMITS")
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                GitCommitOverviewChart(correlation: correlation)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private struct GitTokenOverviewChart: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    private var height: CGFloat {
        correlation.hasTokens ? 96 : 44
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GitOverviewYAxis(ticks: correlation.tokenTicks)
                .frame(height: height)
            Canvas { context, size in
                GitOverviewChartDrawing.drawGrid(
                    context: &context,
                    size: size,
                    tickCount: correlation.tokenTicks.count
                )
                GitOverviewChartDrawing.drawLineArea(
                    context: &context,
                    size: size,
                    values: correlation.tokenValues,
                    maxValue: max(correlation.tokenMax, 1),
                    color: Color.stxAccent
                )
            }
            .frame(height: height)
        }
        .opacity(correlation.hasTokens ? 1 : 0.5)
    }
}

private struct GitCommitOverviewChart: View {
    let correlation: GitActivityViewModel.OverviewCorrelation

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                GitOverviewYAxis(ticks: correlation.commitTicks)
                    .frame(height: 96)
                Canvas { context, size in
                    GitOverviewChartDrawing.drawGrid(
                        context: &context,
                        size: size,
                        tickCount: correlation.commitTicks.count
                    )
                    GitOverviewChartDrawing.drawBars(
                        context: &context,
                        size: size,
                        values: correlation.commitValues,
                        maxValue: max(correlation.commitMax, 1),
                        color: Color.primary.opacity(0.55)
                    )
                }
                .frame(height: 96)
            }
            GitOverviewXAxisLabels(ticks: correlation.dateTicks)
                .padding(.leading, 52)
        }
    }
}

private struct GitOverviewYAxis: View {
    let ticks: [GitActivityViewModel.OverviewAxisTick]

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                Text(tick.label)
                    .font(.sora(8).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if index < ticks.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 44)
    }
}

private struct GitOverviewXAxisLabels: View {
    let ticks: [GitActivityViewModel.OverviewDateTick]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                Text(tick.label)
                    .font(.sora(8))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                if index < ticks.count - 1 {
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

private enum GitOverviewChartDrawing {
    static func drawGrid(context: inout GraphicsContext, size: CGSize, tickCount: Int) {
        let count = max(tickCount, 2)
        for index in 0..<count {
            let y = size.height * CGFloat(index) / CGFloat(count - 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.stxStroke), lineWidth: 1)
        }
    }

    static func drawLineArea(
        context: inout GraphicsContext,
        size: CGSize,
        values: [Int],
        maxValue: Int,
        color: Color
    ) {
        let points = values.enumerated().map { index, value in
            point(index: index, count: values.count, value: value, maxValue: maxValue, size: size)
        }
        guard let first = points.first, let last = points.last else { return }

        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }

        var area = Path()
        area.move(to: CGPoint(x: first.x, y: size.height))
        for point in points {
            area.addLine(to: point)
        }
        area.addLine(to: CGPoint(x: last.x, y: size.height))
        area.closeSubpath()

        context.fill(area, with: .color(color.opacity(0.16)))
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    static func drawBars(
        context: inout GraphicsContext,
        size: CGSize,
        values: [Int],
        maxValue: Int,
        color: Color
    ) {
        guard !values.isEmpty else { return }
        let slotWidth = size.width / CGFloat(values.count)
        let barWidth = max(2, min(18, slotWidth * 0.55))

        for (index, value) in values.enumerated() where value > 0 {
            let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
            let height = max(2, size.height * min(max(normalized, 0), 1))
            let x = CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
            let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(color))
        }
    }

    private static func point(index: Int, count: Int, value: Int, maxValue: Int, size: CGSize) -> CGPoint {
        let x = count <= 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(count - 1)
        let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
        let y = size.height - size.height * min(max(normalized, 0), 1)
        return CGPoint(x: x, y: y)
    }
}

private struct GitChurnTable: View {
    let rows: [GitActivityViewModel.OverviewRepoRow]
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitTableTitle(title: "CODE CHURN BY REPO", detail: detail)
            StxRule()
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                GitChurnTableRow(row: row)
                if index < rows.count - 1 { StxRule() }
            }
        }
        .gitMainCard()
    }
}

private struct GitChurnTableRow: View {
    let row: GitActivityViewModel.OverviewRepoRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(.sora(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(row.insertionsLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(GitPalette.add)
            Text(row.deletionsLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(GitPalette.del)
            Text(row.filesLabel)
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct GitRecentCommitsTable: View {
    let rows: [GitActivityViewModel.OverviewCommitRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitTableTitle(title: "RECENT COMMITS", detail: "\(rows.count) shown")
            StxRule()
            if rows.isEmpty {
                GitInlineEmptyState("No commits in this range.")
                    .padding(14)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    GitRecentCommitTableRow(row: row)
                    if index < rows.count - 1 { StxRule() }
                }
            }
        }
        .gitMainCard()
    }
}

private struct GitRecentCommitTableRow: View {
    let row: GitActivityViewModel.OverviewCommitRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.subject)
                .font(.sora(11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(row.repoName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.shortHash)
                Text(row.churnLabel)
                Spacer(minLength: 6)
                Text(row.dateLabel)
            }
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
