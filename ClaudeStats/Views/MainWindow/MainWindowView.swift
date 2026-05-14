import SwiftUI

/// Top-level page shown in the main window's detail column.
enum MainPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, sessions, usage, activity, git, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .sessions: "Sessions"
        case .usage: "Usage"
        case .activity: "Activity"
        case .git: "Git"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sessions: "list.bullet.rectangle"
        case .usage: "chart.bar.xaxis"
        case .activity: "waveform"
        case .git: "arrow.triangle.branch"
        case .settings: "gearshape"
        }
    }
}

/// The main app window: a `NavigationSplitView` with a fixed sidebar of pages
/// and a detail column that swaps content. The window holds an
/// activation-policy reference for its lifetime so the app shows a Dock icon
/// while it's open (see ``DockVisibilityCoordinator``).
struct MainWindowView: View {
    static let windowID = "main-window"

    @Environment(AppEnvironment.self) private var env
    @SceneStorage("mainWindow.selectedPage") private var pageRaw: String = MainPage.dashboard.rawValue
    @State private var page: MainPage = .dashboard

    private var availablePages: [MainPage] {
        var pages: [MainPage] = [.dashboard, .sessions, .usage]
        if env.preferences.aiActivityAnalysisEnabled { pages.append(.activity) }
        if env.preferences.gitTrackingEnabled { pages.append(.git) }
        pages.append(.settings)
        return pages
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.stxBackground)
        }
        .navigationTitle("")
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $page) {
            Section {
                row(.dashboard)
            }
            Section("Stats") {
                row(.sessions)
                row(.usage)
                if env.preferences.aiActivityAnalysisEnabled { row(.activity) }
                if env.preferences.gitTrackingEnabled { row(.git) }
            }
            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(Color.stxAccent)
            Text("CLAUDE STATS")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func row(_ p: MainPage) -> some View {
        Label(p.title, systemImage: p.symbol)
            .font(.sora(12))
            .tag(p)
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
        case .settings:
            CenteredPaneContainer { SettingsView() }
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
