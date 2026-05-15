import SwiftUI

struct GitRepoWorkspaceView: View {
    let repo: GitRepo
    @State private var vm: GitRepoGraphViewModel

    private static let rowHeight: CGFloat = 36
    private static let laneSpacing: CGFloat = 14
    private static let railPad: CGFloat = 15
    private static let nodeRadius: CGFloat = 3

    init(repo: GitRepo) {
        self.repo = repo
        _vm = State(wrappedValue: GitRepoGraphViewModel())
    }

    #if DEBUG
    init(repo: GitRepo, previewGraph: GitGraph?) {
        self.repo = repo
        if let previewGraph {
            _vm = State(wrappedValue: GitRepoGraphViewModel(previewGraph: previewGraph))
        } else {
            _vm = State(wrappedValue: GitRepoGraphViewModel())
        }
    }
    #endif

    private var railWidth: CGFloat {
        CGFloat((vm.layout?.maxColumn ?? 0)) * Self.laneSpacing + Self.railPad * 2
    }

    var body: some View {
        HStack(spacing: 0) {
            graphColumn
                .frame(minWidth: 220, idealWidth: 520, maxWidth: .infinity)

            Rectangle()
                .fill(Color.stxStroke)
                .frame(width: 1)

            GitCommitInspector(repo: repo, vm: vm)
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 318)
        }
        .task(id: "\(repo.id)|\(vm.limit)") {
            await vm.loadGraph(repo: repo)
        }
        .task(id: "\(repo.id)|\(vm.selectedHash ?? "")") {
            await vm.loadDetail(repo: repo)
        }
        .task(id: "\(repo.id)|\(vm.selectedHash ?? "")|\(vm.diffPath ?? "")") {
            await vm.loadDiff(repo: repo)
        }
    }

    private var graphColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            graphHeader
            StxRule()
            graphContent
        }
    }

    private var graphHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.displayName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(repo.rootPath)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(repo.rootPath)
            }
            Spacer(minLength: 10)
            if vm.isGraphLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if let graph = vm.graph {
                Text("\(graph.commits.count)\(graph.truncated ? "+" : "") commits")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if graph.truncated {
                    Button {
                        vm.loadMore()
                    } label: {
                        Label("More", systemImage: "plus")
                            .font(.sora(10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stxAccent)
                    .help("Load more commits")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var graphContent: some View {
        if let layout = vm.layout, !layout.rows.isEmpty {
            FadingScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(layout.rows) { row in
                        GitGraphRowView(
                            row: row,
                            rowHeight: Self.rowHeight,
                            laneSpacing: Self.laneSpacing,
                            railPad: Self.railPad,
                            nodeRadius: Self.nodeRadius,
                            railWidth: railWidth,
                            isSelected: vm.selectedHash == row.commit.hash
                        ) {
                            vm.selectCommit(row.commit.hash)
                        }
                    }
                }
            }
        } else if vm.isGraphLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GitWorkspaceInlineEmptyState("No commits to graph.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GitCommitInspector: View {
    let repo: GitRepo
    let vm: GitRepoGraphViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
            StxRule()
            if vm.diffPath != nil {
                diffBody
            } else {
                commitBody
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            Text(vm.diffPath == nil ? "COMMIT INSPECTOR" : "FILE DIFF")
                .font(.sora(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.stxMuted)
            Spacer()
            if vm.isDetailLoading || vm.isDiffLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var commitBody: some View {
        if let commit = vm.selectedCommit {
            FadingScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    commitSummary(commit)
                    if let detail = vm.commitDetail {
                        commitMessage(detail)
                        changedFiles(detail)
                    } else if vm.isDetailLoading {
                        GitWorkspaceInlineEmptyState("Loading commit detail.")
                    } else {
                        GitWorkspaceInlineEmptyState("Couldn't load this commit.")
                    }
                }
                .padding(14)
            }
        } else {
            GitWorkspaceInlineEmptyState("Select a commit.")
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
                    Text("merge")
                        .font(.sora(9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }

            if !commit.refs.isEmpty {
                FlowPills(refs: commit.refs)
            }
        }
        .padding(12)
        .gitWorkspaceCard()
    }

    @ViewBuilder
    private func commitMessage(_ detail: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MESSAGE")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if detail.body.isEmpty {
                Text("No commit body.")
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("FILES CHANGED")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                Spacer()
                Text("+\(detail.totalInsertions) -\(detail.totalDeletions)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(12)

            StxRule()

            if detail.files.isEmpty {
                GitWorkspaceInlineEmptyState(detail.isMerge ? "Merge commit with no file diff." : "No file changes.")
                    .padding(12)
            } else {
                ForEach(detail.files) { file in
                    Button {
                        vm.openDiff(path: file.path)
                    } label: {
                        HStack(spacing: 8) {
                            if file.isBinary {
                                Text("bin")
                                    .font(.sora(9).monospacedDigit())
                                    .foregroundStyle(Color.stxMuted)
                            } else {
                                Text("+\(file.insertions)")
                                    .font(.sora(9).monospacedDigit())
                                    .foregroundStyle(GitPalette.add)
                                Text("-\(file.deletions)")
                                    .font(.sora(9).monospacedDigit())
                                    .foregroundStyle(GitPalette.del)
                            }
                            Text(file.path)
                                .font(.sora(10))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.stxMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open diff for \(file.path)")
                    if file.id != detail.files.last?.id { StxRule() }
                }
            }
        }
        .gitWorkspaceCard()
    }

    @ViewBuilder
    private var diffBody: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    GitBackButton(help: "Back to changed files") {
                        vm.closeDiff()
                    }
                    Text(vm.diffPath ?? "")
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(vm.diffPath ?? "")
                }
                .padding(12)
                .gitWorkspaceCard()

                if vm.isDiffLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if let diff = vm.fileDiff {
                    diffLines(diff)
                } else {
                    GitWorkspaceInlineEmptyState("Couldn't load this diff.")
                }
            }
            .padding(14)
        }
    }

    private func diffLines(_ diff: FileDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if diff.isBinary {
                GitWorkspaceInlineEmptyState("Binary file.")
                    .padding(12)
            } else if diff.lines.isEmpty {
                GitWorkspaceInlineEmptyState("No diff lines.")
                    .padding(12)
            } else {
                ForEach(diff.lines) { line in
                    DiffLineRow(line: line)
                }
            }
        }
        .gitWorkspaceCard()
    }
}

private struct FlowPills: View {
    let refs: [GitRef]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                    GitRefPill(ref: ref)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted.opacity(0.65))
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 6)
            Text(line.newLine.map(String.init) ?? "")
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted.opacity(0.65))
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 8)
            Text(prefix)
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(prefixColor)
                .frame(width: 14, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "-"
        case .hunkHeader: "@"
        default: " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .addition: GitPalette.add
        case .deletion: GitPalette.del
        case .hunkHeader: Color.stxAccent
        default: Color.stxMuted
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .fileHeader, .hunkHeader: Color.stxMuted
        case .addition: GitPalette.add
        case .deletion: GitPalette.del
        case .context: .primary
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: GitPalette.add.opacity(0.10)
        case .deletion: GitPalette.del.opacity(0.10)
        case .hunkHeader: Color.stxAccent.opacity(0.08)
        default: .clear
        }
    }
}

private struct GitWorkspaceInlineEmptyState: View {
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
        self
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
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
