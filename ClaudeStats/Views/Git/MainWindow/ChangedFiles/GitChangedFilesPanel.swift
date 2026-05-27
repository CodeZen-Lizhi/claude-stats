import SwiftUI

struct GitChangedFilesPanel: View {
    let title: String
    let summary: String
    let emptyMessage: String
    let rows: [GitChangedFileRowModel]
    let onOpen: (GitChangedFileRowModel) -> Void

    init(
        title: String = L10n.string("git.changed_files.title", defaultValue: "FILES CHANGED"),
        summary: String,
        emptyMessage: String,
        rows: [GitChangedFileRowModel],
        onOpen: @escaping (GitChangedFileRowModel) -> Void = { _ in }
    ) {
        self.title = title
        self.summary = summary
        self.emptyMessage = emptyMessage
        self.rows = rows
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StxRule()
            if rows.isEmpty {
                GitWorkspaceInlineEmptyState(emptyMessage)
                    .padding(12)
            } else {
                rowsList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 10))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Spacer()
            Text(summary)
                .font(.sora(10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, GitChangedFileRow.contentHorizontalInset)
        .padding(.vertical, 12)
    }

    private var rowsList: some View {
        let lastID = rows.last?.id

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                GitChangedFileRow(model: row, onOpen: onOpen)
                    .frame(maxWidth: .infinity, minHeight: GitChangedFileRow.rowHeight, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        StxRule()
                            .opacity(row.id == lastID ? 0 : 1)
                            .allowsHitTesting(false)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Changed files panel") {
    GitChangedFilesPanel(
        summary: "+427 -23",
        emptyMessage: "No file changes.",
        rows: [
            GitChangedFileRowModel(
                commitFile: CommitFileChange(
                    path: ".agents/skills/vercel/optimize-server-auth-actions.md",
                    insertions: 96,
                    deletions: 0
                )
            ),
            GitChangedFileRowModel(
                commitFile: CommitFileChange(path: "AGENTS.md", insertions: 78, deletions: 0)
            ),
            GitChangedFileRowModel(
                commitFile: CommitFileChange(path: "Resources/state-machine.png", insertions: -1, deletions: -1)
            ),
            GitChangedFileRowModel(
                workingTreeChange: GitWorkingTreeChange(
                    path: "src/components/CommitInspector/FilesChangedPanel.swift",
                    oldPath: "src/components/CommitInspector/ChangedFiles.swift",
                    indexStatus: "R",
                    worktreeStatus: "M",
                    kind: .renamed
                )
            )
        ]
    )
    .frame(width: 320)
    .padding(14)
    .background(AppSurface.backgroundFill)
}
#endif
