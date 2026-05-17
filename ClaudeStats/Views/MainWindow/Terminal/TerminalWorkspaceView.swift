import GhosttyEmbed
import SwiftUI

struct TerminalWorkspaceView: View {
    @Environment(AppEnvironment.self) private var env

    @ObservedObject var store: EmbeddedTerminalStore
    @State private var pendingClose: EmbeddedTerminalTabItem?

    private var selectedTab: EmbeddedTerminalTabItem? {
        store.tabs.first { $0.id == store.selectedTabID }
    }

    var body: some View {
        TerminalChromeView(
            store: store,
            chromeMode: env.preferences.terminalChromeMode,
            backgroundStyle: env.preferences.terminalBackgroundStyle,
            onCloseTab: close,
            onCloseSelectedTab: closeSelected
        )
        .onAppear {
            store.ensureDefaultTab()
        }
        .confirmationDialog(
            "Close Terminal?",
            isPresented: Binding(
                get: { pendingClose != nil },
                set: { if !$0 { pendingClose = nil } }
            ),
            presenting: pendingClose
        ) { tab in
            Button("Close", role: .destructive) {
                _ = store.closeTab(id: tab.id, force: true)
                pendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                pendingClose = nil
            }
        } message: { _ in
            Text("The terminal still has a running process. Closing it will kill the process.")
        }
    }

    private func close(_ tab: EmbeddedTerminalTabItem) {
        if store.closeTab(id: tab.id, force: false) {
            pendingClose = nil
        } else {
            pendingClose = tab
        }
    }

    private func closeSelected() {
        guard let selectedTab else { return }
        close(selectedTab)
    }
}

#if DEBUG
#Preview("Terminal workspace") {
    TerminalWorkspaceView(store: EmbeddedTerminalStore())
        .environment(AppEnvironment.preview())
        .frame(width: 900, height: 560)
}
#endif
