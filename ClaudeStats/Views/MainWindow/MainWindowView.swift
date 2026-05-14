import SwiftUI

/// Top-level page shown in the main window's detail column. Settings live in
/// their own "settings mode" (see ``SettingsModeView``), not as a `MainPage`.
enum MainPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, sessions, usage, activity, git
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .sessions: "Sessions"
        case .usage: "Usage"
        case .activity: "Activity"
        case .git: "Git"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sessions: "list.bullet.rectangle"
        case .usage: "chart.bar.xaxis"
        case .activity: "waveform"
        case .git: "arrow.triangle.branch"
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
    @SceneStorage("mainWindow.selectedPage") private var pageRaw: String = MainPage.dashboard.rawValue
    @SceneStorage("mainWindow.sidebarVisible") private var sidebarVisible: Bool = true
    @SceneStorage("mainWindow.inSettingsMode") private var inSettingsMode: Bool = false
    @State private var page: MainPage = .dashboard
    @State private var toggleHovering = false
    @State private var trafficLights = TrafficLightPositioner()

    private var availablePages: [MainPage] {
        var pages: [MainPage] = [.dashboard, .sessions, .usage]
        if env.preferences.aiActivityAnalysisEnabled { pages.append(.activity) }
        if env.preferences.gitTrackingEnabled { pages.append(.git) }
        return pages
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            if inSettingsMode {
                SettingsModeView(onExit: {
                    withAnimation(.easeInOut(duration: 0.2)) { inSettingsMode = false }
                })
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    if sidebarVisible {
                        SidebarColumn(
                            page: $page,
                            availablePages: availablePages,
                            onOpenSettings: {
                                withAnimation(.easeInOut(duration: 0.2)) { inSettingsMode = true }
                            }
                        )
                        .frame(width: 220)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    DetailPanel(roundedLeading: sidebarVisible) { detail }
                }
                .transition(.opacity)
            }

            if !inSettingsMode {
                sidebarToggle
                    .padding(.leading, 81)
                    .padding(.top, 11)
            }
        }
        .ignoresSafeArea()
        .background(WindowAccessor { window in
            trafficLights.attach(to: window)
        })
        .onAppear {
            page = MainPage(rawValue: pageRaw) ?? .dashboard
            if !availablePages.contains(page) { page = .dashboard }
            DockVisibilityCoordinator.shared.acquire()
            Log.app.info("Main window opened on page \(page.rawValue, privacy: .public)")
        }
        .onDisappear {
            DockVisibilityCoordinator.shared.release()
            Log.app.info("Main window closed")
        }
        .onChange(of: page) { _, new in pageRaw = new.rawValue }
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, on in
            if !on && page == .activity { page = .dashboard }
        }
        .onChange(of: env.preferences.gitTrackingEnabled) { _, on in
            if !on && page == .git { page = .dashboard }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsInMainWindow)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { inSettingsMode = true }
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
        case .sessions:
            CenteredPaneContainer { SessionListView(mode: .interactive) }
        case .usage:
            CenteredPaneContainer { UsageView(mode: .interactive) }
        case .activity:
            CenteredPaneContainer { AIActivityView(mode: .interactive) }
        case .git:
            CenteredPaneContainer { GitActivityView() }
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
