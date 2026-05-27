import Testing
@testable import ClaudeStats

@Suite("Git changed file row model")
struct GitChangedFileRowModelTests {
    @Test("Commit file rows expose openable churn")
    func commitFileRowsExposeOpenableChurn() {
        let row = GitChangedFileRowModel(
            commitFile: CommitFileChange(path: "Sources/App.swift", insertions: 12, deletions: 3)
        )

        #expect(row.id == "commit|Sources/App.swift")
        #expect(row.path == "Sources/App.swift")
        #expect(row.churn == .text(insertions: 12, deletions: 3))
        #expect(row.kindBadge == nil)
        #expect(row.statusBadges.isEmpty)
        #expect(row.openPath == "Sources/App.swift")
        #expect(row.isOpenable)
        #expect(row.helpText == "Open diff for Sources/App.swift")
    }

    @Test("Binary commit rows use binary churn")
    func binaryCommitRowsUseBinaryChurn() {
        let row = GitChangedFileRowModel(
            commitFile: CommitFileChange(path: "Resources/state-machine.png", insertions: -1, deletions: -1)
        )

        #expect(row.churn == .binary)
        #expect(row.path == "Resources/state-machine.png")
        #expect(row.openPath == "Resources/state-machine.png")
        #expect(row.isOpenable)
    }

    @Test("Root commit paths are preserved")
    func rootCommitPathsArePreserved() {
        let row = GitChangedFileRowModel(
            commitFile: CommitFileChange(path: "AGENTS.md", insertions: 1, deletions: 0)
        )

        #expect(row.path == "AGENTS.md")
        #expect(row.openPath == "AGENTS.md")
        #expect(row.accessibilityLabel == "Open diff for AGENTS.md")
    }

    @Test("Long commit paths are preserved for middle truncation in the row")
    func longCommitPathsArePreserved() {
        let path = ".agents/skills/vercel/optimize-server-auth-actions.md"
        let row = GitChangedFileRowModel(
            commitFile: CommitFileChange(path: path, insertions: 96, deletions: 0)
        )

        #expect(row.path == path)
        #expect(row.openPath == path)
        #expect(row.churn == .text(insertions: 96, deletions: 0))
    }

    @Test("Renamed worktree rows display old and new paths")
    func renamedWorktreeRowsDisplayOldAndNewPaths() {
        let row = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "Sources/NewName.swift",
                oldPath: "Sources/OldName.swift",
                indexStatus: "R",
                worktreeStatus: " ",
                kind: .renamed
            )
        )

        #expect(row.id == "worktree|R |Sources/OldName.swift|Sources/NewName.swift")
        #expect(row.path == "Sources/OldName.swift -> Sources/NewName.swift")
        #expect(row.churn == nil)
        #expect(row.kindBadge == .init(label: "REN", help: "Renamed", tone: .tag))
        #expect(row.statusBadges.map(\.label) == ["staged"])
        #expect(row.openPath == nil)
        #expect(!row.isOpenable)
    }

    @Test("Copied and untracked worktree rows use add tone")
    func copiedAndUntrackedWorktreeRowsUseAddTone() {
        let copied = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "Sources/Copied.swift",
                oldPath: "Sources/Original.swift",
                indexStatus: "C",
                worktreeStatus: " ",
                kind: .copied
            )
        )
        let untracked = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "Sources/New.swift",
                oldPath: nil,
                indexStatus: "?",
                worktreeStatus: "?",
                kind: .untracked
            )
        )

        #expect(copied.kindBadge == .init(label: "CPY", help: "Copied", tone: .add))
        #expect(copied.statusBadges.map(\.label) == ["staged"])
        #expect(untracked.kindBadge == .init(label: "NEW", help: "Untracked", tone: .add))
        #expect(untracked.statusBadges.map(\.label) == ["unstaged"])
    }

    @Test("Worktree staged and unstaged badges follow porcelain status")
    func worktreeBadgesFollowPorcelainStatus() {
        let staged = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "staged.swift",
                oldPath: nil,
                indexStatus: "M",
                worktreeStatus: " ",
                kind: .modified
            )
        )
        let unstaged = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "unstaged.swift",
                oldPath: nil,
                indexStatus: " ",
                worktreeStatus: "M",
                kind: .modified
            )
        )
        let both = GitChangedFileRowModel(
            workingTreeChange: GitWorkingTreeChange(
                path: "both.swift",
                oldPath: nil,
                indexStatus: "M",
                worktreeStatus: "M",
                kind: .modified
            )
        )

        #expect(staged.statusBadges.map(\.label) == ["staged"])
        #expect(unstaged.statusBadges.map(\.label) == ["unstaged"])
        #expect(both.statusBadges.map(\.label) == ["staged", "unstaged"])
        #expect(both.kindBadge == .init(label: "MOD", help: "Modified", tone: .head))
    }
}
