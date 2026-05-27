import SwiftUI

/// Main-window Sessions page. The global app sidebar remains mounted; this view
/// owns the Sessions-specific browser and detail panes inside the content area.
struct SessionsWorkspaceView: View {
    @Binding var destination: SessionsDestination
    @Environment(AppEnvironment.self) private var env
    @State private var pendingDeleteSessions: [Session] = []
    @State private var deleteConfirmationPresented = false
    @State private var deleteFailureMessage: String?
    @State private var isDeleting = false

    private var selectedSession: Session? {
        guard case .session(let id) = destination else { return nil }
        return env.store.sessions(for: env.preferences.selectedProvider).first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            SessionSidebarColumn(destination: $destination, onRequestDelete: requestDelete)
                .frame(width: 260)
                .background(Color.primary.opacity(0.025))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.stxStroke.opacity(0.7))
                        .frame(width: 1)
                }

            sessionsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(deleteConfirmationTitle, isPresented: $deleteConfirmationPresented) {
            Button(L10n.string("sessions.delete.confirm", defaultValue: "Move to Trash"), role: .destructive) {
                Task { await deletePendingSessions() }
            }
            Button(L10n.string("common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(L10n.string("sessions.delete.failed.title", defaultValue: "Some sessions could not be deleted"),
               isPresented: Binding(
                   get: { deleteFailureMessage != nil },
                   set: { if !$0 { deleteFailureMessage = nil } }
               )) {
            Button(L10n.string("common.ok", defaultValue: "OK"), role: .cancel) { deleteFailureMessage = nil }
        } message: {
            Text(deleteFailureMessage ?? "")
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in clearInvalidSelectionIfNeeded() }
        .onChange(of: env.preferences.selectedProvider) { _, _ in destination = .overview }
        .onAppear { clearInvalidSelectionIfNeeded() }
    }

    @ViewBuilder
    private var sessionsDetail: some View {
        switch destination {
        case .overview:
            SessionsOverviewDetailView(
                onSelectSession: { session in destination = .session(session.id) },
                onDeleteSession: { session in requestDelete([session]) }
            )
        case .session:
            if let selectedSession {
                CenteredPaneContainer { SessionDetailView(session: selectedSession, onDelete: { requestDelete([$0]) }) }
            } else {
                SessionsOverviewDetailView(
                    onSelectSession: { session in destination = .session(session.id) },
                    onDeleteSession: { session in requestDelete([session]) }
                )
            }
        }
    }

    private func clearInvalidSelectionIfNeeded() {
        guard case .session(let id) = destination else { return }
        let sessions = env.store.sessions(for: env.preferences.selectedProvider)
        if !sessions.contains(where: { $0.id == id }) {
            destination = .overview
        }
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteSessions.count
        if count == 1 {
            return L10n.string("sessions.delete.single.title", defaultValue: "Delete session?")
        }
        return L10n.format("sessions.delete.batch.title", defaultValue: "Delete %@ sessions?", "\(count)")
    }

    private var deleteConfirmationMessage: String {
        if pendingDeleteSessions.count > 1 {
            return L10n.string(
                "sessions.delete.confirmation.batch.message",
                defaultValue: "The original transcripts will be moved to Trash. Token, cost, Dashboard, and Git history stay available. Project folders, Git repos, and Codex settings are not deleted. If any delete fails, successful deletes stay deleted and failed sessions remain in the list."
            )
        }
        return L10n.string(
            "sessions.delete.confirmation.message",
            defaultValue: "The original transcript will be moved to Trash. Token, cost, Dashboard, and Git history stay available. Project folders, Git repos, and Codex settings are not deleted."
        )
    }

    private func requestDelete(_ sessions: [Session]) {
        let unique = Dictionary(grouping: sessions, by: \.id)
            .compactMap { $0.value.first }
            .sorted { ($0.stats?.lastActivity ?? $0.lastModified) > ($1.stats?.lastActivity ?? $1.lastModified) }
        guard !unique.isEmpty, !isDeleting else { return }
        pendingDeleteSessions = unique
        deleteConfirmationPresented = true
    }

    private func deletePendingSessions() async {
        guard !pendingDeleteSessions.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        let result = await env.store.deleteSessions(pendingDeleteSessions)
        pendingDeleteSessions = []
        clearInvalidSelectionIfNeeded()
        if result.failedCount > 0 {
            let first = result.firstFailureMessage ?? L10n.string("sessions.delete.failed.unknown", defaultValue: "Unknown error.")
            deleteFailureMessage = L10n.format(
                "sessions.delete.failed.message",
                defaultValue: "%@ sessions were moved to Trash. %@ failed. First error: %@",
                "\(result.deletedCount)",
                "\(result.failedCount)",
                first
            )
        }
    }
}

#if DEBUG
#Preview("Sessions workspace") {
    @Previewable @State var destination: SessionsDestination = .overview

    return SessionsWorkspaceView(destination: $destination)
        .environment(AppEnvironment.preview())
        .frame(width: 920, height: 640)
        .background(Color.stxBackground)
}
#endif
