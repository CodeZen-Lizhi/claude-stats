import SwiftUI
import AppKit

/// The main window's left column. Two regions stacked vertically:
///   - Top nav (Dashboard, STATS for usage/leaderboards/activity, then TOOLS
///     for configuration, Git, and terminal tools).
///   - SESSIONS section: a Codex-style collapsible tree of projects, each
///     expanding to its own sessions. The header carries a "collapse all"
///     button (active only when any project is expanded) and a sort menu.
/// Settings stays pinned at the bottom.
///
/// Picking a project row toggles its disclosure. Picking a session row sets
/// ``selectedSessionID`` on the parent and the detail pane switches to
/// ``SessionDetailView``. Picking a top nav row clears ``selectedSessionID``.
///
/// Lives over a window-level `NSVisualEffectView` (`.sidebar` material), so
/// its own background stays transparent.
struct SidebarColumn: View {
    @Binding var page: MainPage
    @Binding var selectedSessionID: String?
    @Binding var sessionsExpanded: Bool
    var availablePages: [MainPage]
    var onOpenSettings: () -> Void
    var onOpenNetwork: () -> Void
    var onOpenOps: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var sessionsVM = SessionListViewModel()
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light buttons (window uses `.hiddenTitleBar`).
            Color.clear.frame(height: 44)

            navRow(.dashboard)

            sectionHeader("STATS")
            navRow(.usage)
            navRow(.leaderboards)
            if env.preferences.aiActivityAnalysisEnabled { navRow(.activity) }

            sectionHeader("TOOLS")
            navRow(.configurations)
            navRow(.configs)
            if env.preferences.gitTrackingEnabled { navRow(.git) }
            if env.preferences.systemMonitorEnabled { navRow(.system) }
            navRow(.skills)
            SidebarRow(
                title: "Ops",
                symbol: "wrench.and.screwdriver",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearSearchFocus()
                onOpenOps()
            }
            SidebarRow(
                title: "Network",
                symbol: "network",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearSearchFocus()
                onOpenNetwork()
            }
            navRow(.terminal)

            sessionsSection

            SidebarRow(title: "Settings", symbol: "gearshape", isSelected: false) {
                clearSearchFocus()
                onOpenSettings()
            }
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearSearchFocus() }
        }
        .onAppear { refreshSessionGroups() }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in refreshSessionGroups() }
        .onChange(of: env.preferences.selectedProvider) { _, _ in refreshSessionGroups() }
        .onChange(of: env.preferences.costEstimationMode) { _, _ in refreshSessionGroups() }
    }

    // MARK: - Top nav

    @ViewBuilder
    private func navRow(_ p: MainPage) -> some View {
        if availablePages.contains(p) {
            SidebarRow(
                title: p.title,
                symbol: p.symbol,
                isSelected: selectedSessionID == nil && page == p
            ) {
                clearSearchFocus()
                selectedSessionID = nil
                page = p
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    // MARK: - SESSIONS section

    @ViewBuilder
    private var sessionsSection: some View {
        @Bindable var vm = sessionsVM
        sessionsHeader

        if sessionsExpanded {
            searchField(vm: vm)
            sessionsTree(vm: vm)
        } else {
            // Take up the remaining space so Settings stays pinned at the bottom.
            Spacer(minLength: 0)
        }
    }

    private var sessionsHeader: some View {
        HStack(spacing: 6) {
            Button {
                clearSearchFocus()
                withAnimation(.easeInOut(duration: 0.18)) { sessionsExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(sessionsExpanded ? 0 : -90))
                    Text("SESSIONS")
                        .font(.sora(10, weight: .semibold))
                        .tracking(1.0)
                }
                .foregroundStyle(Color.stxMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if sessionsExpanded {
                HeaderIconButton(
                    systemName: "arrow.down.right.and.arrow.up.left",
                    help: "Collapse all projects",
                    enabled: !sessionsVM.expandedProjects.isEmpty
                ) {
                    clearSearchFocus()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sessionsVM.expandedProjects.removeAll()
                    }
                }

                Menu {
                    Picker("Sort by", selection: $sessionsVM.sortOrder) {
                        ForEach(SessionListViewModel.SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort sessions")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func searchField(vm: SessionListViewModel) -> some View {
        @Bindable var vm = vm
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
            TextField("Search", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .focused($searchFieldFocused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func sessionsTree(vm: SessionListViewModel) -> some View {
        let groups = vm.projectGroups

        if groups.isEmpty {
            sessionsEmptyState(
                hasQuery: !vm.searchText.isEmpty,
                isLoading: env.store.isLoading,
                hasProviderSessions: vm.hasProviderSessions
            )
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            FadingScrollView(chrome: .plain) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        let isExpanded = vm.expandedProjects.contains(group.id)
                        ProjectSidebarRow(
                            name: group.displayName,
                            count: group.count,
                            isExpanded: isExpanded
                        ) {
                            clearSearchFocus()
                            withAnimation(.easeInOut(duration: 0.18)) { vm.toggle(group.id) }
                        }
                        if isExpanded {
                            ForEach(group.sessions) { session in
                                SessionSidebarRow(
                                    session: session,
                                    isSelected: selectedSessionID == session.id
                                ) {
                                    clearSearchFocus()
                                    selectedSessionID = session.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionsEmptyState(hasQuery: Bool, isLoading: Bool, hasProviderSessions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading && !hasProviderSessions {
                Text("Scanning…").font(.sora(11)).foregroundStyle(Color.stxMuted)
            } else if hasQuery {
                Text("No matches").font(.sora(11)).foregroundStyle(Color.stxMuted)
            } else {
                Text("No sessions yet").font(.sora(11)).foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func refreshSessionGroups() {
        sessionsVM.refresh(
            from: env.store,
            provider: env.preferences.selectedProvider,
            costMode: env.preferences.costEstimationMode
        )
    }

    private func clearSearchFocus() {
        searchFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

// MARK: - Top nav row

/// One sidebar nav row: an icon + label inside a rounded selection chip.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var trailingSymbol: String?
    var showsTrailingOnHover = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                Text(LocalizedStringKey(title))
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                Spacer(minLength: 0)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .opacity(showsTrailingOnHover ? (hovering ? 1 : 0) : 1)
                        .frame(width: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Project & session rows

/// A project header row inside the SESSIONS tree: folder glyph, name, count,
/// and a disclosure chevron that rotates when the group is expanded.
private struct ProjectSidebarRow: View {
    let name: String
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 16)
                Text(name)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

/// A session leaf row under an expanded project: title + relative date.
/// Indented to align under the project's folder glyph.
private struct SessionSidebarRow: View {
    let session: Session
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    private var title: String {
        if let t = session.stats?.title, !t.isEmpty { return t }
        return session.externalID
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sora(11))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted.opacity(0.95))
                    .lineLimit(1)
                Text(Format.relativeDate(session.stats?.lastActivity ?? session.lastModified))
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 36) // align under the project's folder glyph
        .padding(.trailing, 8)
        .onHover { hovering = $0 }
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

// MARK: - Header icon button

/// Small icon-only button used in the SESSIONS section header. Dims to muted
/// when disabled (no expanded projects to collapse, etc.).
private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? Color.stxMuted : Color.stxMuted.opacity(0.35))
                .frame(width: 22, height: 20)
                .background {
                    if enabled && hovering {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

#if DEBUG
#Preview("Sidebar column") {
    @Previewable @State var page: MainPage = .dashboard
    @Previewable @State var sessionID: String? = nil
    return SidebarColumn(
        page: $page,
        selectedSessionID: $sessionID,
        sessionsExpanded: .constant(false),
        availablePages: [.dashboard, .configurations, .configs, .usage, .activity, .git],
        onOpenSettings: {},
        onOpenNetwork: {},
        onOpenOps: {}
    )
    .environment(AppEnvironment.preview())
    .frame(width: 240, height: 600)
    .background(VisualEffectBackground())
}
#endif
