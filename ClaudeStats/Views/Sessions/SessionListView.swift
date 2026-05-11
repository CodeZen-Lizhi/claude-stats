import SwiftUI

struct SessionListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = SessionListViewModel()

    var body: some View {
        @Bindable var vm = vm
        let store = env.store
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search project or title", text: $vm.searchText)
                    .textFieldStyle(.plain)
                Picker("Sort", selection: $vm.sortOrder) {
                    ForEach(SessionListViewModel.SortOrder.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            content(store: store)
        }
    }

    @ViewBuilder
    private func content(store: SessionStore) -> some View {
        if !store.dataDirectoryExists {
            ContentUnavailableView {
                Label("No Claude Code Data", systemImage: "tray")
            } description: {
                Text("Couldn't find \(ClaudePaths.default.projectsDirectory.path).")
            }
        } else {
            let sessions = vm.sessions(from: store)
            if sessions.isEmpty {
                if store.isLoading && store.sessions.isEmpty {
                    ProgressView("Scanning sessions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        store.sessions.isEmpty ? "No Sessions" : "No Matches",
                        systemImage: store.sessions.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(store.sessions.isEmpty
                            ? "No usable transcripts found yet."
                            : "No session matches “\(vm.searchText)”.")
                    )
                }
            } else {
                FadingScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            SessionRow(session: session)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            if index < sessions.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Populated") {
    SessionListView()
        .environment(AppEnvironment.preview())
        .frame(width: 380, height: 420)
}

#Preview("Empty") {
    SessionListView()
        .environment(AppEnvironment.preview(populated: false))
        .frame(width: 380, height: 420)
}
#endif
