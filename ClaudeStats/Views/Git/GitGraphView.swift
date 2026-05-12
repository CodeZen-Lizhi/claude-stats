import SwiftUI

/// The commit DAG for one repository — gitk/GitLens-style: colored branch lanes
/// drawn per row, commit nodes, merge bends, ref pills, author initials, subject,
/// date. Reached by tapping a repo row in ``GitActivityView``; tapping a commit
/// row expands its per-file churn (`git show --numstat`, fetched lazily).
struct GitGraphView: View {
    let repo: GitRepo
    var onBack: () -> Void

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

    private var railWidth: CGFloat {
        CGFloat((layout?.maxColumn ?? 0)) * Self.laneSpacing + Self.railPad * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            content
        }
        .task(id: [repo.id, "\(limit)"]) {
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
                                detail(for: row.commit)
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

    @ViewBuilder
    private func detail(for commit: GraphCommit) -> some View {
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
        .padding(.leading, railWidth + 14)
        .padding(.trailing, 14)
        .padding(.bottom, 8)
    }

    private func toggle(_ hash: String) {
        if expandedHash == hash { expandedHash = nil; return }
        expandedHash = hash
        guard fileChanges[hash] == nil else { return }
        let r = repo
        Task {
            let fc = await Task.detached(priority: .userInitiated) { GitAnalyzer().fileChanges(for: hash, in: r) }.value
            fileChanges[hash] = fc
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
            Text(Format.shortDate(row.commit.date))
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
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
    GitGraphView(repo: GitRepo(rootPath: FileManager.default.currentDirectoryPath), onBack: {})
        .environment(AppEnvironment.preview())
        .frame(width: 420, height: 520)
        .background(Color.stxBackground)
}
#endif
