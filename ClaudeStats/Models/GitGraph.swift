import Foundation

/// A ref (branch / tag / HEAD) pointing at a commit, parsed from `git log`'s
/// `%D` decoration field.
struct GitRef: Sendable, Hashable {
    enum Kind: Sendable { case head, branch, tag }
    let kind: Kind
    /// `"main"`, `"v1.0"`, `"claude/fix-drawer-card-bugs"`, …
    let name: String
}

/// One commit as it appears in the graph: enough to draw the DAG (parents) and
/// the row (refs, author, date, subject). No diff stats — those are fetched
/// lazily per row via ``GitAnalyzer/fileChanges(for:in:)``.
struct GraphCommit: Sendable, Identifiable, Hashable {
    let hash: String
    /// Parent hashes in git's order; more than one ⇒ a merge commit.
    let parentHashes: [String]
    let refs: [GitRef]
    let author: String
    let authorEmail: String
    let date: Date
    let subject: String

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
    var shortHash: String { String(hash.prefix(7)) }
}

/// The commit list for one repo, in display order (`--date-order`, newest first).
struct GitGraph: Sendable {
    let repo: GitRepo
    let commits: [GraphCommit]
    /// `true` when the log hit the requested limit (more history exists).
    let truncated: Bool
}

/// One file's churn within a commit — the expanded-row detail in the graph.
/// `insertions`/`deletions` are `-1` for binary files (git prints `-`).
struct CommitFileChange: Sendable, Identifiable, Hashable {
    let path: String
    let insertions: Int
    let deletions: Int
    var id: String { path }
    var isBinary: Bool { insertions < 0 || deletions < 0 }
}
