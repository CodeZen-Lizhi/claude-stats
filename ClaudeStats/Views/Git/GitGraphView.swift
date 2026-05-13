import SwiftUI

/// The commit DAG for one repository — gitk/GitLens-style: colored branch lanes
/// drawn per row, commit nodes, merge bends, ref pills, author initials, subject,
/// date. Reached by tapping a repo row in ``GitActivityView``; tapping a commit
/// row expands its per-file churn (`git show --numstat`, fetched lazily).
struct GitGraphView: View {
    let repo: GitRepo
    var onBack: () -> Void
    private let isPreview: Bool

    // Rail geometry — `rowHeight` must be fixed so each row's `Canvas` lines up.
    private static let rowHeight: CGFloat = 38
    private static let laneSpacing: CGFloat = 14
    private static let railPad: CGFloat = 11
    private static let nodeRadius: CGFloat = 3

    @State private var graph: GitGraph?
    @State private var layout: GraphLayout?
    @State private var isLoading = false
    @State private var limit = 200
    @State private var expandedHash: String?
    @State private var fileChanges: [String: [CommitFileChange]] = [:]

    init(repo: GitRepo, onBack: @escaping () -> Void) {
        self.repo = repo
        self.onBack = onBack
        self.isPreview = false
    }

    #if DEBUG
    /// Preview-only: starts already populated with a canned commit DAG (and
    /// optionally per-commit file churn) so the Xcode canvas renders the lanes,
    /// merges and detail rows — the live view shells out to `git`.
    init(previewGraph: GitGraph,
         fileChanges: [String: [CommitFileChange]] = [:],
         onBack: @escaping () -> Void = {}) {
        self.repo = previewGraph.repo
        self.onBack = onBack
        self.isPreview = true
        _graph = State(initialValue: previewGraph)
        _layout = State(initialValue: GraphLayout.build(previewGraph.commits))
        _fileChanges = State(initialValue: fileChanges)
    }
    #endif

    private var railWidth: CGFloat {
        CGFloat((layout?.maxColumn ?? 0)) * Self.laneSpacing + Self.railPad * 2
    }
    private func laneX(_ column: Int) -> CGFloat { Self.railPad + CGFloat(column) * Self.laneSpacing }
    private func laneColor(_ idx: Int) -> Color { Color.stxRamp[idx % Color.stxRamp.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
        }
        .task(id: [repo.id, "\(limit)"]) {
            if isPreview { return }
            isLoading = true
            let r = repo
            let n = limit
            let g = await Task.detached(priority: .userInitiated) { GitAnalyzer().graph(for: r, limit: n) }.value
            graph = g
            layout = g.map { GraphLayout.build($0.commits) }
            isLoading = false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                BracketBox(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Back to git overview")

            Text(repo.displayName.uppercased())
                .font(.sora(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isLoading { ProgressView().controlSize(.mini) }
            Spacer()
            if let g = graph {
                Text("\(g.commits.count)\(g.truncated ? "+" : "") commit\(g.commits.count == 1 ? "" : "s")")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                if g.truncated {
                    Button("More") { limit += 200 }
                        .buttonStyle(.plain)
                        .font(.sora(9, weight: .semibold))
                        .foregroundStyle(Color.stxAccent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let layout, !layout.rows.isEmpty {
            FadingScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(layout.rows) { row in
                        VStack(spacing: 0) {
                            GraphRowView(row: row, maxColumn: layout.maxColumn,
                                         rowHeight: Self.rowHeight, laneSpacing: Self.laneSpacing,
                                         railPad: Self.railPad, nodeRadius: Self.nodeRadius,
                                         railWidth: railWidth,
                                         isExpanded: expandedHash == row.id) {
                                toggle(row.commit.hash)
                            }
                            if expandedHash == row.id {
                                detail(for: row)
                            }
                        }
                    }
                }
            }
        } else if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Text("No commits to graph.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    /// The expanded detail block under a commit row. The left rail gutter draws
    /// the lanes that continue past this row as same-colored *dashed* verticals,
    /// so the graph reads as connected across the inserted block.
    @ViewBuilder
    private func detail(for row: GraphLayout.Row) -> some View {
        let commit = row.commit
        HStack(spacing: 8) {
            railContinuation(for: row).frame(width: railWidth)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.shortHash).font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxAccent)
                    Text("\(commit.author) <\(commit.authorEmail)>")
                        .font(.sora(9)).foregroundStyle(Color.stxMuted).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.shortDate(commit.date)).font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
                }
                if let changes = fileChanges[commit.hash] {
                    if changes.isEmpty {
                        Text(commit.isMerge ? "Merge commit — no file diff." : "No file changes.")
                            .font(.sora(9)).foregroundStyle(Color.stxMuted.opacity(0.7))
                    } else {
                        ForEach(changes) { fc in
                            HStack(spacing: 6) {
                                if fc.isBinary {
                                    Text("bin").font(.sora(9).monospacedDigit()).foregroundStyle(Color.stxMuted)
                                } else {
                                    Text("+\(fc.insertions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.add)
                                    Text("−\(fc.deletions)").font(.sora(9).monospacedDigit()).foregroundStyle(GitPalette.del)
                                }
                                Text(fc.path)
                                    .font(.sora(9)).foregroundStyle(.primary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } else {
                    Text("Loading…").font(.sora(9)).foregroundStyle(Color.stxMuted.opacity(0.7))
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.05))
    }

    private func railContinuation(for row: GraphLayout.Row) -> some View {
        Canvas { ctx, size in
            var seen = Set<Int>()
            var lanes: [(column: Int, colorIndex: Int)] = row.passThrough.map { ($0.column, $0.colorIndex) }
            lanes += row.edgesDown.map { ($0.toColumn, $0.colorIndex) }
            for lane in lanes where seen.insert(lane.column).inserted {
                var p = Path()
                p.move(to: CGPoint(x: laneX(lane.column), y: 0))
                p.addLine(to: CGPoint(x: laneX(lane.column), y: size.height))
                ctx.stroke(p, with: .color(laneColor(lane.colorIndex)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1.5, 3.5]))
            }
        }
    }

    private func toggle(_ hash: String) {
        let willExpand = expandedHash != hash
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedHash = willExpand ? hash : nil
        }
        guard willExpand, fileChanges[hash] == nil else { return }
        if isPreview {
            withAnimation(.easeInOut(duration: 0.15)) { fileChanges[hash] = [] }
            return
        }
        let r = repo
        Task {
            let fc = await Task.detached(priority: .userInitiated) { GitAnalyzer().fileChanges(for: hash, in: r) }.value
            withAnimation(.easeInOut(duration: 0.15)) { fileChanges[hash] = fc }
        }
    }
}

// MARK: - One row

private struct GraphRowView: View {
    let row: GraphLayout.Row
    let maxColumn: Int
    let rowHeight: CGFloat
    let laneSpacing: CGFloat
    let railPad: CGFloat
    let nodeRadius: CGFloat
    let railWidth: CGFloat
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var hovering = false

    private func x(_ column: Int) -> CGFloat { railPad + CGFloat(column) * laneSpacing }
    private func color(_ idx: Int) -> Color { Color.stxRamp[idx % Color.stxRamp.count] }

    var body: some View {
        HStack(spacing: 8) {
            rail
            GitAvatar(name: row.commit.author, email: row.commit.authorEmail).frame(width: 20, height: 20)
            ForEach(Array(row.commit.refs.enumerated()), id: \.offset) { _, ref in
                RefPill(ref: ref)
            }
            Text(TitleSanitizer.sanitize(row.commit.subject) ?? row.commit.subject)
                .font(.sora(11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(Format.relativeDate(row.commit.date))
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
                .fixedSize()
                .help(Format.shortDate(row.commit.date))
        }
        .padding(.trailing, 14)
        .frame(height: rowHeight)
        .background((hovering || isExpanded) ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }

    private var rail: some View {
        Canvas { ctx, size in
            let h = size.height
            let midY = h / 2
            // 1. lanes that just pass through
            for lane in row.passThrough {
                var p = Path()
                p.move(to: CGPoint(x: x(lane.column), y: 0))
                p.addLine(to: CGPoint(x: x(lane.column), y: h))
                ctx.stroke(p, with: .color(color(lane.colorIndex)), lineWidth: 1.6)
            }
            // 2. incoming segment into the node (skip for branch tips — nothing above)
            if !row.isBranchTip {
                var p = Path()
                p.move(to: CGPoint(x: x(row.column), y: 0))
                p.addLine(to: CGPoint(x: x(row.column), y: midY))
                ctx.stroke(p, with: .color(color(row.colorIndex)), lineWidth: 1.6)
            }
            // 3. outgoing edges to parents (lower half)
            for e in row.edgesDown {
                var p = Path()
                let xf = x(e.fromColumn), xt = x(e.toColumn)
                p.move(to: CGPoint(x: xf, y: midY))
                if xf == xt {
                    p.addLine(to: CGPoint(x: xt, y: h))
                } else {
                    p.addCurve(to: CGPoint(x: xt, y: h),
                               control1: CGPoint(x: xf, y: h * 0.78),
                               control2: CGPoint(x: xt, y: midY + (h - midY) * 0.22))
                }
                ctx.stroke(p, with: .color(color(e.colorIndex)), lineWidth: 1.6)
            }
            // 4. the node
            let c = CGPoint(x: x(row.column), y: midY)
            let disc = Path(ellipseIn: CGRect(x: c.x - nodeRadius, y: c.y - nodeRadius,
                                              width: nodeRadius * 2, height: nodeRadius * 2))
            ctx.fill(disc, with: .color(color(row.colorIndex)))
            if row.commit.isMerge {
                let ring = Path(ellipseIn: CGRect(x: c.x - nodeRadius - 2.5, y: c.y - nodeRadius - 2.5,
                                                  width: (nodeRadius + 2.5) * 2, height: (nodeRadius + 2.5) * 2))
                ctx.stroke(ring, with: .color(color(row.colorIndex)), lineWidth: 1.6)
            }
        }
        .frame(width: railWidth)
    }
}

// MARK: - Bits

private enum GitPalette {
    static let add = Color(red: 0.36, green: 0.68, blue: 0.34)
    static let del = Color(red: 0.86, green: 0.30, blue: 0.24)
    static let head = Color(red: 0.20, green: 0.48, blue: 0.86)
    static let tag = Color(red: 0.78, green: 0.58, blue: 0.10)
}

private struct RefPill: View {
    let ref: GitRef

    private var tint: Color {
        switch ref.kind {
        case .head: GitPalette.head
        case .tag: GitPalette.tag
        case .branch: Color.primary.opacity(0.45)
        }
    }

    var body: some View {
        Text(ref.name)
            .font(.sora(8, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(ref.kind == .branch ? 0.16 : 0.85), in: Capsule())
            .foregroundStyle(ref.kind == .branch ? Color.primary : Color.white)
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: ref.kind == .branch ? 1 : 0))
    }
}

/// Initials avatar with a colour deterministically derived from the email.
struct GitAvatar: View {
    let name: String
    let email: String

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).prefix(2)
        let chars = words.compactMap(\.first).map { String($0).uppercased() }
        if chars.isEmpty { return "?" }
        return chars.joined()
    }

    private var color: Color {
        var h: UInt64 = 0xcbf29ce484222325
        for b in email.lowercased().utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }   // FNV-1a
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.42, brightness: 0.62)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(
                Text(initials)
                    .font(.sora(8, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

#if DEBUG
#Preview("Git graph") {
    GitGraphView(previewGraph: .preview(), fileChanges: GitGraph.previewFileChanges())
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 520)
        .background(Color.stxBackground)
}

#Preview("Git graph — empty") {
    GitGraphView(previewGraph: GitGraph(repo: GitRepo(rootPath: "/Users/dev/projects/empty"),
                                        commits: [], truncated: false))
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 520)
        .background(Color.stxBackground)
}
#endif
