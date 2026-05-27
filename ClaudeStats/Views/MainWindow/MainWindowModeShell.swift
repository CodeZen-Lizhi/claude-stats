import AppKit
import SwiftUI

enum MainWindowMode: String, Sendable {
    case app
    case settings
}

enum MainWindowMotion {
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
    @Binding var appSidebarWidth: Double

    private let appSidebar: AppSidebar
    private let settingsSidebar: SettingsSidebar
    private let appDetail: AppDetail
    private let settingsDetail: SettingsDetail

    init(
        mode: MainWindowMode,
        sidebarVisible: Bool,
        boundaryFalloffEnabled: Bool,
        appSidebarWidth: Binding<Double>,
        @ViewBuilder appSidebar: () -> AppSidebar,
        @ViewBuilder settingsSidebar: () -> SettingsSidebar,
        @ViewBuilder appDetail: () -> AppDetail,
        @ViewBuilder settingsDetail: () -> SettingsDetail
    ) {
        self.mode = mode
        self.sidebarVisible = sidebarVisible
        self.boundaryFalloffEnabled = boundaryFalloffEnabled
        _appSidebarWidth = appSidebarWidth
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
        .overlay(alignment: .leading) {
            if mode == .app && sidebarVisible {
                MainWindowSidebarResizeHandle(width: $appSidebarWidth)
                    .offset(x: sidebarWidth - 4)
                    .zIndex(4)
            }
        }
    }

    private var sidebarWidth: CGFloat {
        switch mode {
        case .app:
            sidebarVisible ? CGFloat(Preferences.clampedMainWindowSidebarWidth(appSidebarWidth)) : 0
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
                    .frame(width: CGFloat(Preferences.clampedMainWindowSidebarWidth(appSidebarWidth)))
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

private struct MainWindowSidebarResizeHandle: View {
    @Binding var width: Double
    @State private var dragStartWidth: Double?
    @State private var hovering = false
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.stxAccent.opacity(hovering || dragStartWidth != nil ? 0.8 : 0))
                    .frame(width: 3, height: 52)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartWidth ?? width
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        width = Preferences.clampedMainWindowSidebarWidth(start + value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onHover { isHovering in
                hovering = isHovering
                if isHovering && !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !isHovering && cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .help(L10n.string("main_window.sidebar.resize", defaultValue: "Drag to resize sidebar"))
    }
}

#if DEBUG
#Preview("Main window shell") {
    @Previewable @State var sidebarWidth = Preferences.defaultMainWindowSidebarWidth
    return MainWindowModeShell(
        mode: .settings,
        sidebarVisible: true,
        boundaryFalloffEnabled: true,
        appSidebarWidth: $sidebarWidth
    ) {
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
