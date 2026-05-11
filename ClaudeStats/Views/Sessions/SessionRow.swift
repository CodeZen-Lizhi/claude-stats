import SwiftUI
import AppKit

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.provider.iconSystemName)
                .foregroundStyle(session.provider.accentColor)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectDisplayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(session.stats?.title ?? session.externalID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.relativeDate(session.stats?.lastActivity ?? session.lastModified))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let stats = session.stats {
                        Label(Format.tokens(stats.totalTokens), systemImage: "number")
                            .labelStyle(.titleAndIcon)
                        Text(Format.cost(stats.totalCost))
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal Transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            }
            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button("Open Project Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    List(Session.previewSamples) { SessionRow(session: $0) }
        .listStyle(.inset)
        .frame(width: 380, height: 200)
}
#endif
