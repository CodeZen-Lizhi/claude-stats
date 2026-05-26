import SwiftUI

enum MainWindowMode: String, Sendable {
    case app
    case settings
}

enum MainWindowMotion {
    static let appSidebarWidth: CGFloat = 240
    static let settingsSidebarWidth: CGFloat = 220

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

    static var appSidebarTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    static var secondarySidebarTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    static var settingsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }
}

/// Stable two-column shell for the main window. The app sidebar remains stable
/// while normal pages swap inside the detail panel; settings uses its own
/// sidebar mode.
struct MainWindowModeShell<AppSidebar: View, SettingsSidebar: View, AppDetail: View, SettingsDetail: View>: View {
    let mode: MainWindowMode
    let sidebarVisible: Bool
    let boundaryFalloffEnabled: Bool

    private let appSidebar: AppSidebar
    private let settingsSidebar: SettingsSidebar
    private let appDetail: AppDetail
    private let settingsDetail: SettingsDetail

    init(
        mode: MainWindowMode,
        sidebarVisible: Bool,
        boundaryFalloffEnabled: Bool,
        @ViewBuilder appSidebar: () -> AppSidebar,
        @ViewBuilder settingsSidebar: () -> SettingsSidebar,
        @ViewBuilder appDetail: () -> AppDetail,
        @ViewBuilder settingsDetail: () -> SettingsDetail
    ) {
        self.mode = mode
        self.sidebarVisible = sidebarVisible
        self.boundaryFalloffEnabled = boundaryFalloffEnabled
        self.appSidebar = appSidebar()
        self.settingsSidebar = settingsSidebar()
        self.appDetail = appDetail()
        self.settingsDetail = settingsDetail()
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
        }
    }

    private var detailRoundedLeading: Bool {
        switch mode {
        case .app:
            return sidebarVisible
        case .settings:
            return true
        }
    }

    private var appSidebarIsActive: Bool {
        mode == .app && sidebarVisible
    }

    private var settingsSidebarIsActive: Bool {
        mode == .settings
    }

    private var sidebarDeck: some View {
        ZStack(alignment: .leading) {
            switch mode {
            case .app:
                appSidebar
                    .frame(width: MainWindowMotion.appSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(appSidebarIsActive)
                    .accessibilityHidden(!appSidebarIsActive)
                    .transition(MainWindowMotion.appSidebarTransition)
            case .settings:
                settingsSidebar
                    .frame(width: MainWindowMotion.settingsSidebarWidth)
                    .allowsHitTesting(settingsSidebarIsActive)
                    .accessibilityHidden(!settingsSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            }
        }
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
    } appDetail: {
        Color.stxBackground.overlay(Text("App Detail"))
    } settingsDetail: {
        Color.stxBackground.overlay(Text("Settings Detail"))
    }
    .frame(width: 900, height: 600)
    .background(VisualEffectBackground())
}
#endif
