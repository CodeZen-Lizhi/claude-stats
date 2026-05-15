import SwiftUI
import AppKit

/// Detail pane shown when the user picks a session from the sidebar tree.
/// The layout uses the same `StatCard` + `ModelTable` visual language as the
/// Dashboard so the main window reads as one coherent surface.
///
/// Values are read fresh from the session every render — no view model, since
/// the underlying stats are already cached on ``Session/stats`` by
/// ``SessionStore``. If `stats` is `nil` (transcript hasn't been parsed yet
/// or failed to parse), the view shows a thin placeholder.
struct SessionDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let stats = session.stats {
                statCards(stats)
                modelBreakdown(stats)
            } else {
                missingStatsPlaceholder
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stxMuted)
                Text(session.projectDisplayName)
                    .font(.sora(11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.stxMuted)
            }

            Text(session.stats?.title.nonEmpty ?? session.externalID)
                .font(.sora(22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Stat cards

    @ViewBuilder
    private func statCards(_ stats: SessionStats) -> some View {
        let includeCache = env.preferences.includeCacheInTokens
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(label: "Total tokens", value: Format.tokens(stats.totalTokens(includingCacheRead: includeCache)))
                StatCard(label: "Estimated cost", value: Format.cost(stats.totalCost))
                StatCard(label: "Messages", value: "\(stats.messageCount)")
                StatCard(label: "Last activity", value: Format.relativeDate(stats.lastActivity ?? session.lastModified))
            }
        }
    }

    // MARK: - Model breakdown

    @ViewBuilder
    private func modelBreakdown(_ stats: SessionStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MODEL")
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            ModelTable(
                models: stats.models,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: { env.store.displayName(forModel: $0, provider: session.provider) }
            )
        }
    }

    // MARK: - Missing stats placeholder

    private var missingStatsPlaceholder: some View {
        Text("Transcript stats haven't been parsed yet.")
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            } label: {
                Label("Reveal Transcript", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)

            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                } label: {
                    Label("Open Project Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .font(.sora(11))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
#Preview {
    SessionDetailView(session: Session.previewSamples.first!)
        .environment(AppEnvironment.preview())
        .padding(24)
        .frame(width: 760, height: 600)
        .background(Color.stxBackground)
}
#endif
