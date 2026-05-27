import SwiftUI

/// Main-window Sessions page. The global app sidebar remains mounted; this view
/// owns the Sessions-specific browser and detail panes inside the content area.
struct SessionsWorkspaceView: View {
    @Binding var destination: SessionsDestination
    @Environment(AppEnvironment.self) private var env

    private var selectedSession: Session? {
        guard case .session(let id) = destination else { return nil }
        return env.store.sessions(for: env.preferences.selectedProvider).first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            SessionSidebarColumn(destination: $destination)
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
        .onChange(of: env.store.lastRefreshedAt) { _, _ in clearInvalidSelectionIfNeeded() }
        .onChange(of: env.preferences.selectedProvider) { _, _ in destination = .overview }
        .onAppear { clearInvalidSelectionIfNeeded() }
    }

    @ViewBuilder
    private var sessionsDetail: some View {
        switch destination {
        case .overview:
            SessionsOverviewDetailView { session in
                destination = .session(session.id)
            }
        case .session:
            if let selectedSession {
                CenteredPaneContainer { SessionDetailView(session: selectedSession) }
            } else {
                SessionsOverviewDetailView { session in
                    destination = .session(session.id)
                }
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
