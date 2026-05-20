import SwiftUI

enum MainWindowMode: String, Sendable {
    case app
    case configs
    case settings
    case network
    case ops
}

enum MainWindowMotion {
    static let appSidebarWidth: CGFloat = 240
    static let configsSidebarWidth: CGFloat = 240
    static let settingsSidebarWidth: CGFloat = 220
    static let networkSidebarWidth: CGFloat = 240
    static let opsSidebarWidth: CGFloat = 240

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

    static var configsDetailTransition: AnyTransition {
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

    static var opsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }
}

/// Stable two-column shell for the main window. The sidebar column is a clipped
/// deck that slides between app, configs, settings, network, and ops navigation while the detail panel
/// stays mounted so its leading boundary can move with the sidebar width.
struct MainWindowModeShell<AppSidebar: View, ConfigsSidebar: View, SettingsSidebar: View, NetworkSidebar: View, OpsSidebar: View, AppDetail: View, ConfigsDetail: View, SettingsDetail: View, NetworkDetail: View, OpsDetail: View>: View {
    let mode: MainWindowMode
    let sidebarVisible: Bool
    let boundaryFalloffEnabled: Bool

    private let appSidebar: AppSidebar
    private let configsSidebar: ConfigsSidebar
    private let settingsSidebar: SettingsSidebar
    private let networkSidebar: NetworkSidebar
    private let opsSidebar: OpsSidebar
    private let appDetail: AppDetail
    private let configsDetail: ConfigsDetail
    private let settingsDetail: SettingsDetail
    private let networkDetail: NetworkDetail
    private let opsDetail: OpsDetail

    init(
        mode: MainWindowMode,
        sidebarVisible: Bool,
        boundaryFalloffEnabled: Bool,
        @ViewBuilder appSidebar: () -> AppSidebar,
        @ViewBuilder configsSidebar: () -> ConfigsSidebar,
        @ViewBuilder settingsSidebar: () -> SettingsSidebar,
        @ViewBuilder networkSidebar: () -> NetworkSidebar,
        @ViewBuilder opsSidebar: () -> OpsSidebar,
        @ViewBuilder appDetail: () -> AppDetail,
        @ViewBuilder configsDetail: () -> ConfigsDetail,
        @ViewBuilder settingsDetail: () -> SettingsDetail,
        @ViewBuilder networkDetail: () -> NetworkDetail,
        @ViewBuilder opsDetail: () -> OpsDetail
    ) {
        self.mode = mode
        self.sidebarVisible = sidebarVisible
        self.boundaryFalloffEnabled = boundaryFalloffEnabled
        self.appSidebar = appSidebar()
        self.configsSidebar = configsSidebar()
        self.settingsSidebar = settingsSidebar()
        self.networkSidebar = networkSidebar()
        self.opsSidebar = opsSidebar()
        self.appDetail = appDetail()
        self.configsDetail = configsDetail()
        self.settingsDetail = settingsDetail()
        self.networkDetail = networkDetail()
        self.opsDetail = opsDetail()
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
        case .configs:
            sidebarVisible ? MainWindowMotion.configsSidebarWidth : 0
        case .settings:
            MainWindowMotion.settingsSidebarWidth
        case .network:
            sidebarVisible ? MainWindowMotion.networkSidebarWidth : 0
        case .ops:
            sidebarVisible ? MainWindowMotion.opsSidebarWidth : 0
        }
    }

    private var sidebarDeckOffset: CGFloat {
        switch mode {
        case .app:
            0
        case .configs:
            -MainWindowMotion.appSidebarWidth
        case .settings:
            -(MainWindowMotion.appSidebarWidth + MainWindowMotion.configsSidebarWidth)
        case .network:
            -(MainWindowMotion.appSidebarWidth + MainWindowMotion.configsSidebarWidth + MainWindowMotion.settingsSidebarWidth)
        case .ops:
            -(MainWindowMotion.appSidebarWidth + MainWindowMotion.configsSidebarWidth + MainWindowMotion.settingsSidebarWidth + MainWindowMotion.networkSidebarWidth)
        }
    }

    private var detailRoundedLeading: Bool {
        switch mode {
        case .app:
            return sidebarVisible
        case .configs:
            return sidebarVisible
        case .settings:
            return true
        case .network:
            return sidebarVisible
        case .ops:
            return sidebarVisible
        }
    }

    private var appSidebarIsActive: Bool {
        mode == .app && sidebarVisible
    }

    private var configsSidebarIsActive: Bool {
        mode == .configs && sidebarVisible
    }

    private var settingsSidebarIsActive: Bool {
        mode == .settings
    }

    private var networkSidebarIsActive: Bool {
        mode == .network && sidebarVisible
    }

    private var opsSidebarIsActive: Bool {
        mode == .ops && sidebarVisible
    }

    private var sidebarDeck: some View {
        HStack(spacing: 0) {
            appSidebar
                .frame(width: MainWindowMotion.appSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(appSidebarIsActive)
                .accessibilityHidden(!appSidebarIsActive)

            configsSidebar
                .frame(width: MainWindowMotion.configsSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(configsSidebarIsActive)
                .accessibilityHidden(!configsSidebarIsActive)

            settingsSidebar
                .frame(width: MainWindowMotion.settingsSidebarWidth)
                .allowsHitTesting(settingsSidebarIsActive)
                .accessibilityHidden(!settingsSidebarIsActive)

            networkSidebar
                .frame(width: MainWindowMotion.networkSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(networkSidebarIsActive)
                .accessibilityHidden(!networkSidebarIsActive)

            opsSidebar
                .frame(width: MainWindowMotion.opsSidebarWidth)
                .opacity(sidebarVisible ? 1 : 0)
                .allowsHitTesting(opsSidebarIsActive)
                .accessibilityHidden(!opsSidebarIsActive)
        }
        .frame(
            width: MainWindowMotion.appSidebarWidth + MainWindowMotion.configsSidebarWidth + MainWindowMotion.settingsSidebarWidth + MainWindowMotion.networkSidebarWidth + MainWindowMotion.opsSidebarWidth,
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
            case .configs:
                configsDetail
                    .transition(MainWindowMotion.configsDetailTransition)
                    .zIndex(1)
            case .settings:
                settingsDetail
                    .transition(MainWindowMotion.settingsDetailTransition)
                    .zIndex(1)
            case .network:
                networkDetail
                    .transition(MainWindowMotion.networkDetailTransition)
                    .zIndex(1)
            case .ops:
                opsDetail
                    .transition(MainWindowMotion.opsDetailTransition)
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
    } configsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Overview")
            Spacer()
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
    } opsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Ports")
            Spacer()
        }
        .padding()
    } appDetail: {
        Color.stxBackground.overlay(Text("App Detail"))
    } configsDetail: {
        Color.stxBackground.overlay(Text("Configs Detail"))
    } settingsDetail: {
        Color.stxBackground.overlay(Text("Settings Detail"))
    } networkDetail: {
        Color.stxBackground.overlay(Text("Network Detail"))
    } opsDetail: {
        Color.stxBackground.overlay(Text("Ops Detail"))
    }
    .frame(width: 900, height: 600)
    .background(VisualEffectBackground())
}
#endif
