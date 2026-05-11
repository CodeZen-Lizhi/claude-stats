import SwiftUI

struct SessionListView: View {
    /// `export` renders a static, non-scrolling slice of the sessions scoped to
    /// a ``PeriodSelection`` (no search/sort chrome) so it can be image-captured.
    enum Mode: Hashable { case interactive, export(PeriodSelection) }

    @Environment(AppEnvironment.self) private var env
    @State private var vm = SessionListViewModel()
    var mode: Mode = .interactive

    private static let exportRowLimit = 14

    var body: some View {
        @Bindable var vm = vm
        let store = env.store
        if case .export(let selection) = mode {
            exportContent(store: store, selection: selection)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.stxMuted)
                    TextField("Search project or title", text: $vm.searchText)
                        .textFieldStyle(.plain)
                        .font(.sora(12))
                    Picker("Sort", selection: $vm.sortOrder) {
                        ForEach(SessionListViewModel.SortOrder.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                StxRule()
                content(store: store)
            }
        }
    }

    @ViewBuilder
    private func exportContent(store: SessionStore, selection: PeriodSelection) -> some View {
        let sessions = store.sessions
            .filter { selection.contains($0.stats?.lastActivity ?? $0.lastModified) }
            .prefix(Self.exportRowLimit)
        if sessions.isEmpty {
            Text("No sessions for this period.")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(session: session)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    if index < sessions.count - 1 {
                        StxRule().padding(.horizontal, 12)
                    }
                }
            }
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
            .font(.sora(12))
        } else {
            let sessions = vm.sessions(from: store)
            if sessions.isEmpty {
                if store.isLoading && store.sessions.isEmpty {
                    ProgressView("Scanning sessions…")
                        .font(.sora(11))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        store.sessions.isEmpty ? "No Sessions" : "No Matches",
                        systemImage: store.sessions.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(store.sessions.isEmpty
                            ? "No usable transcripts found yet."
                            : "No session matches “\(vm.searchText)”.")
                    )
                    .font(.sora(12))
                }
            } else {
                FadingScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            SessionRow(session: session)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                            if index < sessions.count - 1 {
                                StxRule().padding(.horizontal, 12)
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
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    SessionListView()
        .environment(AppEnvironment.preview(populated: false))
        .frame(width: 380, height: 420)
        .background(Color.stxBackground)
        .preferredColorScheme(.dark)
}
#endif
