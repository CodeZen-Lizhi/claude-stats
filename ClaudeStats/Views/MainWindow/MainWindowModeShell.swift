import SwiftUI

enum MainWindowMode: String, Sendable {
    case app
    case settings
    case network
}

enum MainWindowMotion {
    static let appSidebarWidth: CGFloat = 240
    static let settingsSidebarWidth: CGFloat = 220
    static let networkSidebarWidth: CGFloat = 240

    private static let detailOffset: CGFloat = 10

    static var modeSwitchAnimation: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.28)
    }

    static var appDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: -detailOffset).combined(with: .opacity),
            removal: .offset(x: -detailOffset).combined(with: .opacity)
        )
    }

    static var settingsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var networkDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }
}

/// Stable two-column shell for the main window. The sidebar column is a clipped
/// deck that slides between app, settings, and network navigation while the detail panel
/// stays mounted so its leading boundary can move with the sidebar width.
struct MainWindowModeShell<AppSidebar: View, SettingsSidebar: View, NetworkSidebar: View, AppDetail: View, SettingsDetail: View, NetworkDetail: View>: View {
    let mode: MainWindowMode
    let sidebarVisible: Bool
    let boundaryFalloffEnabled: Bool

    private let appSidebar: AppSidebar
    private let settingsSidebar: SettingsSidebar
    private let networkSidebar: NetworkSidebar
    private let appDetail: AppDetail
    private let settingsDetail: SettingsDetail
    private let networkDetail: NetworkDetail

    init(
        mode: MainWindowMode,
        sidebarVisible: Bool,
        boundaryFalloffEnabled: Bool,
        @ViewBuilder appSidebar: () -> AppSidebar,
        @ViewBuilder settingsSidebar: () -> SettingsSidebar,
        @ViewBuilder networkSidebar: () -> NetworkSidebar,
        @ViewBuilder appDetail: () -> AppDetail,
        @ViewBuilder settingsDetail: () -> SettingsDetail,
        @ViewBuilder networkDetail: () -> NetworkDetail
    ) {
        self.mode = mode
        self.sidebarVisible = sidebarVisible
        self.boundaryFalloffEnabled = boundaryFalloffEnabled
        self.appSidebar = appSidebar()
        self.settingsSidebar = settingsSidebar()
        self.networkSidebar = networkSidebar()
        self.appDetail = appDetail()
        self.settingsDetail = settingsDetail()
        self.networkDetail = networkDetail()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarDeck
                .frame(width: sidebarWidth, alignment: .leading)
                .clipped()

            DetailPanel(
                roundedLeading: detailRoundedLeading,
                boundaryFalloffEnabled: boundaryFalloffEnabled
            ) {
                detailContent
            }
        }
    }

    private var sidebarWidth: CGFloat {
        switch mode {
        case .app:
            sidebarVisible ? MainWindowMotion.appSidebarWidth : 0
        case .settings:
            MainWindowMotion.settingsSidebarWidth
        case .network:
            sidebarVisible ? MainWindowMotion.networkSidebarWidth : 0
        }
    }

    private var sidebarDeckOffset: CGFloat {
        switch mode {
        case .app:
            0
        case .settings:
            -MainWindowMotion.appSidebarWidth
        case .network:
            -(MainWindowMotion.appSidebarWidth + MainWindowMotion.settingsSidebarWidth)
        }
    }

    private var detailRoundedLeading: Bool {
        switch mode {
        case .app:
            return sidebarVisible
        case .settings:
            return true
        case .network:
            return sidebarVisible
        }
    }

    private var appSidebarIsActive: Bool {
        mode == .app && sidebarVisible
    }

    private var settingsSidebarIsActive: Bool {
        mode == .settings
    }

    private var networkSidebarIsActive: Bool {
        mode == .network && sidebarVisible
    }

    private var sidebarDeck: some View {
        HStack(spacing: 0) {
            appSidebar
                .frame(width: MainWindowMotion.appSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(appSidebarIsActive)
                .accessibilityHidden(!appSidebarIsActive)

            settingsSidebar
                .frame(width: MainWindowMotion.settingsSidebarWidth)
                .allowsHitTesting(settingsSidebarIsActive)
                .accessibilityHidden(!settingsSidebarIsActive)

            networkSidebar
                .frame(width: MainWindowMotion.networkSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(networkSidebarIsActive)
                .accessibilityHidden(!networkSidebarIsActive)
        }
        .frame(
            width: MainWindowMotion.appSidebarWidth + MainWindowMotion.settingsSidebarWidth + MainWindowMotion.networkSidebarWidth,
            alignment: .leading
        )
        .offset(x: sidebarDeckOffset)
    }

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            switch mode {
            case .app:
                appDetail
                    .transition(MainWindowMotion.appDetailTransition)
                    .zIndex(1)
            case .settings:
                settingsDetail
                    .transition(MainWindowMotion.settingsDetailTransition)
                    .zIndex(1)
            case .network:
                networkDetail
                    .transition(MainWindowMotion.networkDetailTransition)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Main window shell") {
    MainWindowModeShell(mode: .settings, sidebarVisible: true, boundaryFalloffEnabled: true) {
        VStack(alignment: .leading) {
            Text("App")
            Spacer()
            Text("Settings")
        }
        .padding()
    } settingsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("General")
            Spacer()
        }
        .padding()
    } networkSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Traffic")
            Spacer()
        }
        .padding()
    } appDetail: {
        Color.stxBackground.overlay(Text("App Detail"))
    } settingsDetail: {
        Color.stxBackground.overlay(Text("Settings Detail"))
    } networkDetail: {
        Color.stxBackground.overlay(Text("Network Detail"))
    }
    .frame(width: 900, height: 600)
    .background(VisualEffectBackground())
}
#endif
