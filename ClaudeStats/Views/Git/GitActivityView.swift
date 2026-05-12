import SwiftUI
import Charts
import AppKit

/// The "Git" view: the commit activity of the repositories you've used Claude
/// Code in (resolved from each session's `cwd`), and how it lines up with your
/// Claude usage. Shells out to `git` — see ``GitAnalyzer``.
///
/// Shown either as a pane inside the menu panel or in its own window, depending
/// on `Preferences.gitOpensInWindow`. Unlike the other panes it has no export
/// mode (the share window doesn't offer it).
struct GitActivityView: View {
    static let windowID = "git-activity"

    @Environment(AppEnvironment.self) private var env
    @State private var vm = GitActivityViewModel()

    private static let addColor = Color(red: 0.36, green: 0.68, blue: 0.34)
    private static let delColor = Color(red: 0.86, green: 0.30, blue: 0.24)

    private struct ReloadKey: Equatable {
        let token: UInt64
        let lastRefreshed: Date?
    }

    var body: some View {
        @Bindable var vm = vm
        let key = ReloadKey(token: vm.reloadToken, lastRefreshed: env.store.lastRefreshedAt)
        return FadingScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                if !vm.gitAvailable {
                    notice("GIT NOT AVAILABLE",
                           "Couldn't run the `git` command. Install the Xcode command-line tools (`xcode-select --install`) and refresh.")
                } else if !vm.hasData {
                    notice("NO GIT ACTIVITY",
                           "None of the projects you've used Claude Code in are git repositories with commits in this window — or the window is too short. Try a wider range.")
                } else {
                    summaryGrid
                    correlationPanel
                    repoTimelinesPanel
                    churnPanel
                    recentCommitsPanel
                }
            }
            .padding(14)
        }
        .task(id: key) {
            await vm.reload(sessions: env.store.sessions)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        @Bindable var vm = vm
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
        Button { vm.onlyMyCommits.toggle() } label: {
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
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    // MARK: Correlation

    private var correlationPanel: some View {
        let points = vm.correlation(sessions: env.store.sessions)
        let hasTokens = points.contains { $0.claudeTokens > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            Text("CLAUDE USAGE vs COMMITS")
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
                Text("CLAUDE TOKENS").font(.sora(8)).tracking(0.6).foregroundStyle(Color.stxMuted)
                tokensChart(points, hasTokens: hasTokens)
                Text("COMMITS").font(.sora(8)).tracking(0.6).foregroundStyle(Color.stxMuted)
                commitsChart(points)
            }
        }
        .stxPanel(12)
    }

    private func tokensChart(_ points: [GitActivityViewModel.CorrelationPoint], hasTokens: Bool) -> some View {
        Chart(points) { p in
            AreaMark(x: .value("When", p.start), y: .value("Tokens", p.claudeTokens))
                .foregroundStyle(Color.stxAccent.opacity(0.16))
            LineMark(x: .value("When", p.start), y: .value("Tokens", p.claudeTokens))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("PER-REPO COMMIT TIMELINE")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            ForEach(vm.repos) { activity in
                StxRule()
                repoTimelineRow(activity)
            }
        }
        .stxPanel(12)
    }

    private func repoTimelineRow(_ activity: RepoActivity) -> some View {
        let buckets = vm.timeline(for: activity)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(activity.repo.displayName)
                    .font(.sora(11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 28)
        }
    }

    // MARK: Churn table

    private var churnPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        let commits = vm.recentCommits()
        let repoNamesByID = Dictionary(vm.repos.map { ($0.repo.id, $0.repo.displayName) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 8) {
            Text("RECENT COMMITS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.primary)
            ForEach(commits) { commit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(TitleSanitizer.sanitize(commit.subject) ?? commit.subject)
                        .font(.sora(11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(repoNamesByID[commit.repoID] ?? "—")
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                        Text("·").foregroundStyle(Color.stxMuted)
                        Text("+\(commit.insertions) −\(commit.deletions)")
                            .font(.sora(9).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                        Spacer(minLength: 8)
                        Text(Format.relativeDate(commit.date))
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
                .padding(.vertical, 2)
            }
        }
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

#if DEBUG
#Preview("Git") {
    GitActivityView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 480)
        .background(Color.stxBackground)
}
#endif
