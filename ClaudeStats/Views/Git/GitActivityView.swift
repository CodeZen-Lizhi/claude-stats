import SwiftUI
import Charts
import AppKit

/// The "Git" view: commit activity from repositories remembered by the
/// configured Git workspace sources, and how session-backed sources line up
/// with AI usage. Shells out to `git` — see ``GitAnalyzer``.
///
/// Shown either as a pane inside the menu panel or in its own window, depending
/// on `Preferences.gitOpensInWindow`. Unlike the other panes it has no export
/// mode (the share window doesn't offer it).
struct GitActivityView: View {
    static let windowID = "git-activity"

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @State private var graphRepo: GitRepo?
    @State private var recentCommitsExpanded = false
    private let previewModel: GitActivityViewModel?
    private let isPreview: Bool

    init() {
        previewModel = nil
        isPreview = false
    }

    #if DEBUG
    /// Preview-only: injects a view model already populated with canned data so
    /// the Xcode canvas shows the real layout (the live view shells out to `git`).
    init(previewModel: GitActivityViewModel) {
        self.previewModel = previewModel
        isPreview = true
    }
    #endif

    private static let addColor = Color(red: 0.36, green: 0.68, blue: 0.34)
    private static let delColor = Color(red: 0.86, green: 0.30, blue: 0.24)
    private static let collapsedRecentCommitCount = 3
    private static let expandedRecentCommitCount = 7

    private struct ReloadKey: Equatable {
        let token: UInt64
        let gitInputRevision: Int
        let sourceIDs: String
    }

    private var activityModel: GitActivityViewModel {
        previewModel ?? env.gitActivity
    }

    var body: some View {
        if let graphRepo {
            GitGraphView(repo: graphRepo, onBack: { self.graphRepo = nil })
        } else {
            overviewBody
        }
    }

    private var overviewBody: some View {
        let model = activityModel
        @Bindable var vm = model
        let sourceIDs = env.preferences.gitWorkspaceSourceIDs
        let key = ReloadKey(
            token: vm.reloadToken,
            gitInputRevision: env.store.gitAttributionRevision,
            sourceIDs: GitWorkspaceSourceCatalog.storageString(for: sourceIDs)
        )
        return AppScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                if !vm.gitAvailable {
                    notice("GIT NOT AVAILABLE",
                           "Couldn't run the `git` command. Install the Xcode command-line tools (`xcode-select --install`) and refresh.")
                } else if !vm.hasData {
                    GitActivityEmptyState(
                        title: L10n.string("git.activity.empty.title", defaultValue: "No git activity"),
                        message: L10n.string("git.activity.empty.message", defaultValue: "No Codex-used Git repos have commits in this range. Try a wider window or disable My Commits."),
                        rangeLabel: vm.range.shortLabel,
                        onlyMyCommits: vm.onlyMyCommits,
                        widerRange: widerRange(after: vm.range),
                        onSelectRange: { vm.range = $0 },
                        onShowAllCommits: { vm.onlyMyCommits = false },
                        onOpenSources: openRepositorySources
                    )
                } else {
                    recentCommitsPanel
                    summaryGrid
                    correlationPanel
                    repoTimelinesPanel
                    churnPanel
                }
            }
            .padding(14)
        }
        .task(id: key) {
            if isPreview { return }
            await vm.reloadIfNeeded(
                sessions: env.store.gitAttributionSessions,
                sourceIDs: sourceIDs,
                gitInputRevision: env.store.gitAttributionRevision
            )
        }
    }

    private func widerRange(after range: GitRange) -> GitRange? {
        switch range {
        case .today: return .last7Days
        case .last7Days: return .last30Days
        case .last30Days: return .last90Days
        case .last90Days: return nil
        }
    }

    private func openRepositorySources() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWindowView.windowID)
        NotificationCenter.default.post(name: .openSettingsInMainWindow, object: SettingsSection.tracking)
    }

    // MARK: Header

    private var headerRow: some View {
        let model = activityModel
        @Bindable var vm = model
        return HStack(spacing: 10) {
            mineToggle
            Spacer()
            if vm.isLoading { ProgressView().controlSize(.mini) }
            HStack(spacing: 8) {
                ForEach(GitRange.allCases) { r in
                    RangeChip(label: r.shortLabel, isSelected: vm.range == r) { vm.range = r }
                }
            }
        }
    }

    private var mineToggle: some View {
        let vm = activityModel
        return Button { vm.onlyMyCommits.toggle() } label: {
            BracketBox(spacing: 6) {
                Image(systemName: vm.onlyMyCommits ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(vm.onlyMyCommits ? Color.stxAccent : Color.stxMuted)
                Text("MY COMMITS")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .help(vm.userEmail.map { "Only count commits authored by \($0)" } ?? "Only count commits by your git user.email")
    }

    // MARK: Summary

    private var summaryGrid: some View {
        let vm = activityModel
        return Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                statCell("Repos", "\(vm.repos.count)")
                statCell("Commits", "\(vm.totalCommits)")
            }
            GridRow {
                statCell("Lines +/−", "\(Format.tokens(vm.totalInsertions))/\(Format.tokens(vm.totalDeletions))")
                statCell("Files touched", "\(vm.totalFilesChanged)")
            }
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        BracketBox(spacing: 7) {
            Text(title.uppercased() + ":")
                .font(.sora(9))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .layoutPriority(-1)
            Text(value)
                .font(.sora(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .stxNumericValueTransition(value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    // MARK: Correlation

    private var correlationPanel: some View {
        let vm = activityModel
        let points = vm.correlationPoints
        let hasTokens = points.contains { $0.aiTokens > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            Text("AI USAGE vs COMMITS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            Text("TOKENS SPENT IN THESE REPOS · COMMITS LANDED · SAME TIMELINE")
                .font(.sora(9))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)

            if points.isEmpty {
                emptyChartNote("Nothing to plot for this range.")
            } else {
                StxRule()
                Text("AI TOKENS").font(.sora(8)).tracking(0.6).foregroundStyle(Color.stxMuted)
                tokensChart(points, hasTokens: hasTokens)
                Text("COMMITS").font(.sora(8)).tracking(0.6).foregroundStyle(Color.stxMuted)
                commitsChart(points)
            }
        }
        .stxPanel(12)
    }

    private func tokensChart(_ points: [GitActivityViewModel.CorrelationPoint], hasTokens: Bool) -> some View {
        Chart(points) { p in
            AreaMark(x: .value("When", p.start), y: .value("Tokens", p.aiTokens))
                .foregroundStyle(Color.stxAccent.opacity(0.16))
                .interpolationMethod(.monotone)
            LineMark(x: .value("When", p.start), y: .value("Tokens", p.aiTokens))
                .foregroundStyle(Color.stxAccent)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text(Format.tokens(v)).font(.sora(8)).foregroundStyle(Color.stxMuted) }
                }
            }
        }
        .chartXScale(domain: barChartDomain(points.map(\.start)))
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: hasTokens ? 70 : 36)
        .opacity(hasTokens ? 1 : 0.5)
    }

    private func commitsChart(_ points: [GitActivityViewModel.CorrelationPoint]) -> some View {
        Chart(points) { p in
            BarMark(x: .value("When", p.start), y: .value("Commits", p.commitCount))
                .foregroundStyle(Color.primary.opacity(0.55))
                .cornerRadius(1)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)").font(.sora(8)).foregroundStyle(Color.stxMuted) }
                }
            }
        }
        .chartXScale(domain: barChartDomain(points.map(\.start)))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.abbreviated).day())
                            .font(.sora(8)).foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 70)
    }

    // MARK: Per-repo timelines

    private var repoTimelinesPanel: some View {
        let vm = activityModel
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("PER-REPO COMMIT TIMELINE")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
                Text("TAP A REPO FOR ITS GRAPH")
                    .font(.sora(8))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
            }
            ForEach(vm.repos) { activity in
                StxRule()
                let buckets = vm.timeline(for: activity)
                RepoTimelineRow(activity: activity,
                                buckets: buckets,
                                domain: barChartDomain(buckets.map(\.start))) {
                    graphRepo = activity.repo
                }
            }
        }
        .stxPanel(12)
    }

    // MARK: Churn table

    private var churnPanel: some View {
        let vm = activityModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("CODE CHURN BY REPO")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            ForEach(vm.repos) { activity in
                HStack(spacing: 8) {
                    Text(activity.repo.displayName)
                        .font(.sora(10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("+\(Format.tokens(activity.insertions))")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Self.addColor)
                    Text("−\(Format.tokens(activity.deletions))")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Self.delColor)
                    Text("·").foregroundStyle(Color.stxMuted)
                    Text("\(activity.filesChanged) file\(activity.filesChanged == 1 ? "" : "s")")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                    Text("\(activity.commitCount)c")
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
            }
        }
    }

    // MARK: Recent commits

    private var recentCommitsPanel: some View {
        let vm = activityModel
        let commits = vm.recentCommits(limit: Self.expandedRecentCommitCount)
        let repoNamesByID = Dictionary(vm.repos.map { ($0.repo.id, $0.repo.displayName) }, uniquingKeysWith: { a, _ in a })
        return RecentCommitsPanel(
            commits: commits,
            repoNamesByID: repoNamesByID,
            collapsedCount: Self.collapsedRecentCommitCount,
            expandedCount: Self.expandedRecentCommitCount,
            isExpanded: $recentCommitsExpanded
        )
    }

    // MARK: Bits

    private func notice(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sora(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
            Text(body)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .stxPanel(12)
    }

    private func emptyChartNote(_ text: String) -> some View {
        Text(text)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    /// X-domain for a bucketed bar chart, padded by half a bucket on each side so
    /// the first/last bars (centred on their bucket start) aren't clipped at the
    /// plot edge. Buckets are evenly spaced, so half the step is the bar's reach.
    private func barChartDomain(_ starts: [Date]) -> ClosedRange<Date> {
        guard let first = starts.first, let last = starts.last else {
            let now = Date.now
            return now ... now.addingTimeInterval(1)
        }
        let step = starts.count >= 2 ? starts[1].timeIntervalSince(starts[0]) : 86_400
        return first.addingTimeInterval(-step / 2) ... last.addingTimeInterval(step / 2)
    }

    private struct RangeChip: View {
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
}

private struct GitActivityEmptyState: View {
    let title: String
    let message: String
    let rangeLabel: String
    let onlyMyCommits: Bool
    let widerRange: GitRange?
    let onSelectRange: (GitRange) -> Void
    let onShowAllCommits: () -> Void
    let onOpenSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                glyph
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.sora(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                filterPill(systemImage: "calendar", text: rangeLabel)
                if onlyMyCommits {
                    filterPill(systemImage: "person.crop.circle", text: L10n.string("My Commits", defaultValue: "My Commits"))
                }
            }

            HStack(spacing: 8) {
                if let widerRange {
                    emptyAction(
                        L10n.format("git.activity.empty.action.wider", defaultValue: "Show %@", widerRange.shortLabel),
                        systemImage: "calendar.badge.plus"
                    ) {
                        onSelectRange(widerRange)
                    }
                }
                if onlyMyCommits {
                    emptyAction(
                        L10n.string("git.activity.empty.action.all_commits", defaultValue: "All commits"),
                        systemImage: "person.2"
                    ) {
                        onShowAllCommits()
                    }
                }
                emptyAction(
                    L10n.string("settings.section.tracking", defaultValue: "Repository Sources"),
                    systemImage: "folder.badge.gearshape"
                ) {
                    onOpenSources()
                }
            }
        }
        .menuBarSurface(.compactCard(fillOpacity: 0.72, cornerRadius: 10, maxWidth: .infinity), padding: 14)
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(Color.stxAccent.opacity(0.14))
            Circle()
                .strokeBorder(Color.stxAccent.opacity(0.34), lineWidth: 1)
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func filterPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.sora(9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Color.primary.opacity(0.045), in: Capsule())
    }

    private func emptyAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.sora(9, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.11), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct RecentCommitsPanel: View {
    let commits: [GitCommit]
    let repoNamesByID: [String: String]
    let collapsedCount: Int
    let expandedCount: Int
    @Binding private var isExpanded: Bool

    init(
        commits: [GitCommit],
        repoNamesByID: [String: String],
        collapsedCount: Int,
        expandedCount: Int,
        isExpanded: Binding<Bool>
    ) {
        self.commits = commits
        self.repoNamesByID = repoNamesByID
        self.collapsedCount = collapsedCount
        self.expandedCount = expandedCount
        self._isExpanded = isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow

            ForEach(visibleCommits) { commit in
                RecentCommitRow(
                    commit: commit,
                    repoName: repoNamesByID[commit.repoID] ?? "—",
                    isNewest: commit.id == commits.first?.id
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: visibleCommits.count)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("RECENT COMMITS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if showsDisclosure {
                disclosureButton
            }
        }
    }

    private var disclosureButton: some View {
        let visibleCount = visibleCommits.count
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Show the latest \(collapsedCount) commits" : "Show the latest \(expandedCount) commits")
        .accessibilityLabel(isExpanded ? "Collapse recent commits" : "Expand recent commits")
        .accessibilityValue("Showing \(visibleCount) of \(commits.count) commits")
    }

    private var visibleCommits: [GitCommit] {
        let count = isExpanded ? expandedCount : collapsedCount
        return Array(commits.prefix(count))
    }

    private var showsDisclosure: Bool {
        commits.count > collapsedCount
    }
}

private struct RecentCommitRow: View {
    let commit: GitCommit
    let repoName: String
    let isNewest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject)
                .font(.sora(11, weight: isNewest ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(repoName)
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·").foregroundStyle(Color.stxMuted)
                Text(commit.shortHash)
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("·").foregroundStyle(Color.stxMuted)
                Text("+\(Format.tokens(commit.insertions)) −\(Format.tokens(commit.deletions))")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                Text(Format.relativeDate(commit.date))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subject), \(repoName), commit \(commit.shortHash), \(Format.relativeDate(commit.date)), \(commit.insertions) insertions, \(commit.deletions) deletions")
    }

    private var subject: String {
        TitleSanitizer.sanitize(commit.subject) ?? commit.subject
    }
}

/// One row of the per-repo commit timeline: repo name + a "drill-in" chevron
/// (a circular tint fades in behind it on hover) and a sparkline of commits.
private struct RepoTimelineRow: View {
    let activity: RepoActivity
    let buckets: [GitBucket]
    let domain: ClosedRange<Date>
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.repo.displayName)
                        .font(.sora(11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    chevron
                    Spacer(minLength: 8)
                    Text("\(activity.commitCount) commit\(activity.commitCount == 1 ? "" : "s")")
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
                Chart(buckets) { b in
                    BarMark(x: .value("When", b.start), y: .value("Commits", b.commitCount))
                        .foregroundStyle(Color.stxAccent.opacity(0.85))
                        .cornerRadius(1)
                }
                .chartXScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(hovering ? Color.primary.opacity(0.75) : Color.stxMuted)
            .frame(width: 16, height: 16)
            .background {
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09))
                    .scaleEffect(hovering ? 1 : 0.6)
                    .opacity(hovering ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

#if DEBUG
#Preview("Git") {
    GitActivityView(previewModel: .preview())
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 560)
        .background(Color.stxBackground)
}

#Preview("Git — empty") {
    GitActivityView(previewModel: .previewEmpty())
        .environment(AppEnvironment.preview(populated: false))
        .frame(width: 380, height: 560)
        .background(Color.stxBackground)
}
#endif
