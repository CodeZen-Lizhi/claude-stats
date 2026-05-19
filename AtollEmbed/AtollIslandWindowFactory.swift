import AppKit
import Defaults

@MainActor
public enum AtollIslandSizing {
    public static let horizontalMargin: CGFloat = 16
    public static let openHeight: CGFloat = 200
    public static let dynamicIslandTopOffset: CGFloat = 6
    public static let dynamicIslandShadowInset: CGFloat = 14
    public static let shadowPadding: CGFloat = 18

    public static func closedSize(for screen: NSScreen) -> CGSize {
        getClosedNotchSize(screen: screen.localizedName)
    }

    public static func contentSize(for screen: NSScreen?, configuration: AtollIslandConfiguration) -> CGSize {
        AtollDefaultsBridge.sync(configuration)
        return requiredContentSize(for: screen)
    }

    public static func windowSize(for screen: NSScreen, configuration: AtollIslandConfiguration) -> CGSize {
        adjustedWindowSize(contentSize(for: screen, configuration: configuration), for: screen)
    }

    public static func frame(for screen: NSScreen, configuration: AtollIslandConfiguration) -> CGRect {
        topCenteredFrame(size: windowSize(for: screen, configuration: configuration), on: screen)
    }

    public static func topCenteredFrame(size: CGSize, on screen: NSScreen) -> CGRect {
        let clampedWidth = min(size.width, screen.frame.width)
        let clampedHeight = min(size.height, screen.frame.height)
        return CGRect(
            x: screen.frame.midX - clampedWidth / 2,
            y: screen.frame.maxY - clampedHeight,
            width: clampedWidth,
            height: clampedHeight
        )
    }

    static func requiredContentSize(for screen: NSScreen?) -> CGSize {
        let screenName = screen?.localizedName
        var baseSize = Defaults[.enableMinimalisticUI]
            ? minimalisticOpenNotchSize
            : CGSize(
                width: AtollDefaultsBridge.resolvedOpenWidth(
                    requested: Defaults[.openNotchWidth],
                    features: AtollDefaultsBridge.featuresFromCurrentDefaults,
                    maxAllowedWidth: maxAllowedNotchWidth(for: screenName)
                ),
                height: openHeight
            )

        let coordinator = DynamicIslandViewCoordinator.shared
        switch coordinator.currentView {
        case .timer:
            baseSize.height = 250
        case .notes, .clipboard:
            baseSize.height = max(baseSize.height, coordinator.notesLayoutState.preferredHeight)
        case .terminal:
            let screenHeight = screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
            let maxFraction = Defaults[.terminalMaxHeightFraction]
            baseSize.height = min(screenHeight * maxFraction, max(300, screenHeight * maxFraction))
        case .stats:
            baseSize = statsAdjustedNotchSize(
                from: baseSize,
                isStatsTabActive: true,
                secondRowProgress: coordinator.statsSecondRowExpansion
            )
        default:
            break
        }

        return addShadowPadding(to: baseSize, isMinimalistic: Defaults[.enableMinimalisticUI])
    }

    static func adjustedWindowSize(_ contentSize: CGSize, for screen: NSScreen) -> CGSize {
        guard shouldUseDynamicIslandMode(for: screen.localizedName) else {
            return contentSize
        }
        return CGSize(
            width: contentSize.width + dynamicIslandShadowInset * 2,
            height: contentSize.height + dynamicIslandTopOffset
        )
    }
}

@MainActor
public enum AtollIslandWindowFactory {
    public static func makeWindow(
        frame: CGRect,
        title: String = "Claude Stats Notch Island"
    ) -> NSPanel {
        let window = DynamicIslandWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.title = title
        window.acceptsMouseMovedEvents = true
        return window
    }
}
