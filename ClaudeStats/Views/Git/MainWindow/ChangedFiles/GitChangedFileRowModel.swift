import Foundation

struct GitChangedFileRowModel: Identifiable, Hashable, Sendable {
    struct Badge: Identifiable, Hashable, Sendable {
        let label: String
        let help: String
        let tone: Tone

        var id: String { "\(label)|\(help)|\(tone.rawValue)" }
    }

    enum Churn: Hashable, Sendable {
        case text(insertions: Int, deletions: Int)
        case binary
    }

    enum Tone: String, Hashable, Sendable {
        case add
        case delete
        case tag
        case head
        case danger
        case muted
    }

    let id: String
    let path: String
    let churn: Churn?
    let kindBadge: Badge?
    let statusBadges: [Badge]
    let openPath: String?
    let helpText: String
    let accessibilityLabel: String

    var isOpenable: Bool { openPath != nil }

    init(commitFile file: CommitFileChange) {
        id = "commit|\(file.id)"
        path = file.path
        churn = file.isBinary ? .binary : .text(insertions: file.insertions, deletions: file.deletions)
        kindBadge = nil
        statusBadges = []
        openPath = file.path
        helpText = "Open diff for \(file.path)"
        accessibilityLabel = "Open diff for \(file.path)"
    }

    init(workingTreeChange change: GitWorkingTreeChange) {
        id = "worktree|\(change.id)"
        path = change.displayPath
        churn = nil
        kindBadge = Self.kindBadge(for: change.kind)
        statusBadges = Self.statusBadges(for: change)
        openPath = nil
        helpText = "\(change.kind.label): \(change.displayPath)"
        accessibilityLabel = "\(change.kind.label), \(change.displayPath)"
    }

    private static func kindBadge(for kind: GitWorkingTreeChange.Kind) -> Badge {
        Badge(label: kind.shortLabel, help: kind.label, tone: tone(for: kind))
    }

    private static func statusBadges(for change: GitWorkingTreeChange) -> [Badge] {
        var badges: [Badge] = []
        if change.isStaged {
            badges.append(Badge(label: "staged", help: "Staged", tone: .muted))
        }
        if change.isUnstaged {
            badges.append(Badge(label: "unstaged", help: "Unstaged", tone: .muted))
        }
        return badges
    }

    private static func tone(for kind: GitWorkingTreeChange.Kind) -> Tone {
        switch kind {
        case .added, .copied, .untracked: return .add
        case .deleted: return .delete
        case .renamed: return .tag
        case .conflicted: return .danger
        case .modified, .changed: return .head
        }
    }
}
