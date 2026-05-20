import AppKit
import SwiftUI

/// Top-level page shown in the main window's detail column. Settings live in
/// their own main-window mode, not as a `MainPage`.
enum MainPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, configurations, usage, leaderboards, activity, git, system, skills, terminal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L10n.string("main_page.dashboard", defaultValue: "Dashboard")
        case .configurations: L10n.string("main_page.switcher", defaultValue: "Switcher")
        case .usage: L10n.string("main_page.usage", defaultValue: "Usage")
        case .leaderboards: L10n.string("main_page.leaderboards", defaultValue: "Leaderboards")
        case .activity: L10n.string("main_page.activity", defaultValue: "Activity")
        case .git: L10n.string("main_page.git", defaultValue: "Git")
        case .system: L10n.string("main_page.system", defaultValue: "System")
        case .skills: "Skills"
        case .terminal: L10n.string("main_page.terminal", defaultValue: "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .configurations: "slider.horizontal.3"
        case .usage: "chart.bar.xaxis"
        case .leaderboards: "trophy"
        case .activity: "waveform"
        case .git: "arrow.triangle.branch"
        case .system: "cpu"
        case .skills: "sparkles"
        case .terminal: "terminal"
        }
    }
}

extension Notification.Name {
    /// Posted by the menu-bar Settings button to ask the main window to enter
    /// settings mode (opening the window first if needed).
    static let openSettingsInMainWindow = Notification.Name("ClaudeStats.openSettingsInMainWindow")
}

/// The main app window: a vibrancy-backed sidebar with a floating rounded
/// detail "card" sitting visually above it (Codex-style shell). The window
/// holds an activation-policy reference for its lifetime so the app shows a
/// Dock icon while it's open (see ``DockVisibilityCoordinator``).
struct MainWindowView: View {
    static let windowID = "main-window"

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("mainWindow.selectedPage") private var pageRaw: String = MainPage.dashboard.rawValue
    @SceneStorage("mainWindow.sidebarVisible") private var sidebarVisible: Bool = true
    @SceneStorage("mainWindow.mode") private var modeRaw: String = MainWindowMode.app.rawValue
    @SceneStorage("mainWindow.settingsSection") private var settingsSectionRaw: String = SettingsSection.general.rawValue
    @SceneStorage("mainWindow.configsSection") private var configsSectionRaw: String = AIConfigsSection.overview.rawValue
    @SceneStorage("mainWindow.configsSearch") private var configsSearchText: String = ""
    @SceneStorage("mainWindow.configsProjectID") private var configsProjectIDRaw: String = ""
    @SceneStorage("mainWindow.configsDocumentID") private var configsDocumentIDRaw: String = ""
    @SceneStorage("mainWindow.networkSection") private var networkSectionRaw: String = NetworkSection.traffic.rawValue
    @SceneStorage("mainWindow.opsSection") private var opsSectionRaw: String = OpsSection.ports.rawValue
    @State private var page: MainPage = .dashboard
    /// Held at the window level so the Sessions mode can preserve selection
    /// while the user moves in and out of the secondary sidebar.
    @State private var selectedSessionID: String?
    @State private var toggleHovering = false
    @State private var trafficLights = TrafficLightPositioner()

    private var availablePages: [MainPage] {
        var pages: [MainPage] = [.dashboard, .configurations, .usage, .leaderboards]
        if env.preferences.aiActivityAnalysisEnabled { pages.append(.activity) }
        if env.preferences.gitTrackingEnabled { pages.append(.git) }
        if env.preferences.systemMonitorEnabled { pages.append(.system) }
        pages.append(.skills)
        pages.append(.terminal)
        return pages
    }

    /// Resolves the currently selected session against the store. Returns nil
    /// if the id was set but the session has since been removed.
    private var selectedSession: Session? {
        guard let id = selectedSessionID else { return nil }
        return env.store.sessions(for: env.preferences.selectedProvider).first { $0.id == id }
    }

    private var mode: MainWindowMode {
        MainWindowMode(rawValue: modeRaw) ?? .app
    }

    private var settingsSection: SettingsSection {
        SettingsSection(rawValue: settingsSectionRaw) ?? .general
    }

    private var configsSection: AIConfigsSection {
        AIConfigsSection(rawValue: configsSectionRaw) ?? .overview
    }

    private var networkSection: NetworkSection {
        NetworkSection(storedRawValue: networkSectionRaw)
    }

    private var opsSection: OpsSection {
        OpsSection(storedRawValue: opsSectionRaw)
    }

    private var settingsSectionBinding: Binding<SettingsSection> {
        Binding(
            get: { settingsSection },
            set: { settingsSectionRaw = $0.rawValue }
        )
    }

    private var configsSectionBinding: Binding<AIConfigsSection> {
        Binding(
            get: { configsSection },
            set: { configsSectionRaw = $0.rawValue }
        )
    }

    private var configsSearchBinding: Binding<String> {
        Binding(
            get: { configsSearchText },
            set: { configsSearchText = $0 }
        )
    }

    private var configsProjectIDBinding: Binding<String> {
        Binding(
            get: { configsProjectIDRaw },
            set: { configsProjectIDRaw = $0 }
        )
    }

    private var configsDocumentIDBinding: Binding<String> {
        Binding(
            get: { configsDocumentIDRaw },
            set: { configsDocumentIDRaw = $0 }
        )
    }

    private var networkSectionBinding: Binding<NetworkSection> {
        Binding(
            get: { networkSection },
            set: { networkSectionRaw = $0.rawValue }
        )
    }

    private var opsSectionBinding: Binding<OpsSection> {
        Binding(
            get: { opsSection },
            set: { opsSectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            MainWindowModeShell(
                mode: mode,
                sidebarVisible: sidebarVisible,
                boundaryFalloffEnabled: env.preferences.detailPanelBoundaryFalloffEnabled
            ) {
                SidebarColumn(
                    page: $page,
                    availablePages: availablePages,
                    onOpenSettings: openSettings,
                    onOpenSessions: openSessions,
                    onOpenConfigs: openConfigs,
                    onOpenNetwork: openNetwork,
                    onOpenOps: openOps
                )
            } sessionsSidebar: {
                SessionSidebarColumn(
                    selectedSessionID: $selectedSessionID,
                    onExit: closeSessions
                )
            } configsSidebar: {
                AIConfigsSidebarColumn(
                    section: configsSectionBinding,
                    searchText: configsSearchBinding,
                    onExit: closeConfigs
                )
            } settingsSidebar: {
                SettingsSidebarColumn(section: settingsSectionBinding, onExit: closeSettings)
            } networkSidebar: {
                NetworkSidebarColumn(store: env.networkDebugger, section: networkSectionBinding, onExit: closeNetwork)
            } opsSidebar: {
                OpsSidebarColumn(section: opsSectionBinding, onExit: closeOps)
            } appDetail: {
                detail
            } sessionsDetail: {
                sessionsDetail
            } configsDetail: {
                AIConfigsDetailView(
                    section: configsSection,
                    searchText: configsSearchText,
                    selectedProjectID: configsProjectIDBinding,
                    selectedDocumentID: configsDocumentIDBinding
                )
            } settingsDetail: {
                SettingsDetailView(section: settingsSection, onSelectSection: selectSettingsSection)
            } networkDetail: {
                NetworkDetailView(section: networkSection)
            } opsDetail: {
                OpsDetailView(store: env.ops, section: opsSection)
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { clearTextFocus() }
            }

            if mode == .app || mode == .sessions || mode == .configs || mode == .network || mode == .ops {
                sidebarToggle
                    .padding(.leading, 81)
                    .padding(.top, 11)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(WindowAccessor { window in
            trafficLights.attach(to: window)
        })
        .onAppear {
            page = MainPage(rawValue: pageRaw) ?? .dashboard
            if !availablePages.contains(page) { page = .dashboard }
            if mode == .sessions { ensureSessionSelection() }
            DockVisibilityCoordinator.shared.acquire()
            Log.app.info("Main window opened on page \(page.rawValue, privacy: .public)")
        }
        .onDisappear {
            DockVisibilityCoordinator.shared.release()
            Log.app.info("Main window closed")
        }
        .onChange(of: page) { _, new in pageRaw = new.rawValue }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            if mode == .sessions { ensureSessionSelection() }
        }
        .onChange(of: env.preferences.selectedProvider) { _, _ in
            if mode == .sessions { ensureSessionSelection() }
        }
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, on in
            if !on && page == .activity { page = .dashboard }
        }
        .onChange(of: env.preferences.gitTrackingEnabled) { _, on in
            if !on && page == .git { page = .dashboard }
        }
        .onChange(of: env.preferences.systemMonitorEnabled) { _, on in
            if !on && page == .system { page = .dashboard }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsInMainWindow)) { notification in
            openSettings(section: notification.object as? SettingsSection)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectMainWindowDestinationFromFloatingStats)) { notification in
            guard let destination = notification.object as? FloatingStatsMainWindowDestination else { return }
            openFloatingStatsDestination(destination)
        }
    }

    // MARK: - Sidebar toggle

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { sidebarVisible.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toggleHovering ? .primary : Color.stxMuted)
                .frame(width: 24, height: 22)
                .background {
                    if toggleHovering {
                        RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { toggleHovering = $0 }
        .help(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .keyboardShortcut("s", modifiers: [.command, .control])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .dashboard:
            DashboardView()
        case .configurations:
            ConfigurationsView()
        case .usage:
            MainUsageView()
        case .leaderboards:
            LeaderboardsView()
        case .activity:
            MainActivityView()
        case .git:
            MainGitActivityView()
        case .system:
            MainSystemMonitorView()
        case .skills:
            SkillsWorkspaceView(store: env.skills)
        case .terminal:
            TerminalWorkspaceView(store: env.terminalStore)
        }
    }

    @ViewBuilder
    private var sessionsDetail: some View {
        if let session = selectedSession {
            CenteredPaneContainer { SessionDetailView(session: session) }
        } else {
            CenteredPaneContainer {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "tray")
                } description: {
                    Text(env.store.isLoading
                         ? "Scanning sessions for \(env.preferences.selectedProvider.shortName)..."
                         : "No sessions for \(env.preferences.selectedProvider.shortName) yet.")
                }
                .font(.sora(12))
            }
        }
    }

    private func clearTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func openSettings() {
        openSettings(section: nil)
    }

    private func openSettings(section: SettingsSection?) {
        if let section {
            settingsSectionRaw = section.rawValue
        }
        transition(to: .settings)
    }

    private func selectSettingsSection(_ section: SettingsSection) {
        settingsSectionRaw = section.rawValue
    }

    private func openSessions() {
        ensureSessionSelection()
        transition(to: .sessions)
    }

    private func openConfigs() {
        transition(to: .configs)
    }

    private func openNetwork() {
        transition(to: .network)
    }

    private func openOps() {
        transition(to: .ops)
    }

    private func closeSettings() {
        transition(to: .app)
    }

    private func closeSessions() {
        transition(to: .app)
    }

    private func closeConfigs() {
        transition(to: .app)
    }

    private func closeNetwork() {
        transition(to: .app)
    }

    private func closeOps() {
        transition(to: .app)
    }

    private func openFloatingStatsDestination(_ destination: FloatingStatsMainWindowDestination) {
        switch destination {
        case .page(let nextPage):
            page = nextPage
            transition(to: .app)
        case .network:
            transition(to: .network)
        }
    }

    private func ensureSessionSelection() {
        let sessions = env.store.sessions(for: env.preferences.selectedProvider)
        if let id = selectedSessionID, sessions.contains(where: { $0.id == id }) { return }
        selectedSessionID = sessions.max { lhs, rhs in
            sessionActivityDate(lhs) < sessionActivityDate(rhs)
        }?.id
    }

    private func sessionActivityDate(_ session: Session) -> Date {
        session.stats?.lastActivity ?? session.lastModified
    }

    private func transition(to nextMode: MainWindowMode) {
        clearTextFocus()
        guard mode != nextMode else { return }

        if reduceMotion {
            modeRaw = nextMode.rawValue
        } else {
            withAnimation(MainWindowMotion.modeSwitchAnimation) {
                modeRaw = nextMode.rawValue
            }
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
