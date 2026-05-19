import AppKit
import CoreGraphics

enum AtollNotchGeometry {
    static let closedFallbackWidth: CGFloat = 185
    static let closedFallbackHeight: CGFloat = 32
    static let openHeight: CGFloat = 200
    static let horizontalMargin: CGFloat = 16
    static let maxWidthInset: CGFloat = 60
    static let shadowPadding: CGFloat = 18
    static let dynamicIslandTopOffset: CGFloat = 6
    static let dynamicIslandShadowInset: CGFloat = 14

    static func openWidth(for preset: NotchIslandSizePreset) -> CGFloat {
        switch preset {
        case .compact: 420
        case .regular: 640
        case .large: 770
        }
    }

    static func openSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect) -> CGSize {
        let maximumWidth = max(80, screenFrame.width - horizontalMargin * 2)
        let targetWidth = min(openWidth(for: preset), maxAllowedOpenWidth(in: screenFrame), maximumWidth)
        let targetHeight = min(openHeight, max(120, screenFrame.height * 0.78))
        return CGSize(width: targetWidth, height: targetHeight)
    }

    static func closedSize(
        in screenFrame: CGRect,
        safeAreaTop: CGFloat,
        visibleMaxY: CGFloat,
        auxiliaryTopLeftWidth: CGFloat? = nil,
        auxiliaryTopRightWidth: CGFloat? = nil
    ) -> CGSize {
        let notchWidth: CGFloat
        if let auxiliaryTopLeftWidth, let auxiliaryTopRightWidth {
            notchWidth = screenFrame.width - auxiliaryTopLeftWidth - auxiliaryTopRightWidth + 4
        } else {
            notchWidth = closedFallbackWidth
        }

        let menuBarHeight = max(0, screenFrame.maxY - visibleMaxY)
        let notchHeight = safeAreaTop > 0 ? safeAreaTop : max(menuBarHeight, closedFallbackHeight)
        return clampedClosedSize(CGSize(width: notchWidth, height: notchHeight), in: screenFrame)
    }

    static func closedSize(for screen: NSScreen) -> CGSize {
        closedSize(
            in: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            visibleMaxY: screen.visibleFrame.maxY,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }

    static func panelCanvasSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect, dynamicIslandMode: Bool) -> CGSize {
        let open = openSize(for: preset, in: screenFrame)
        let width = open.width + (dynamicIslandMode ? dynamicIslandShadowInset * 2 : 0)
        let height = open.height + shadowPadding + (dynamicIslandMode ? dynamicIslandTopOffset : 0)
        return CGSize(width: width, height: min(height, max(120, screenFrame.height * 0.82)))
    }

    static func visualSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect, expanded: Bool, closedSize: CGSize) -> CGSize {
        expanded ? openSize(for: preset, in: screenFrame) : clampedClosedSize(closedSize, in: screenFrame)
    }

    static func visualFrame(
        in screenFrame: CGRect,
        preset: NotchIslandSizePreset,
        expanded: Bool,
        closedSize: CGSize
    ) -> CGRect {
        let size = visualSize(for: preset, in: screenFrame, expanded: expanded, closedSize: closedSize)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func panelFrame(in screenFrame: CGRect, preset: NotchIslandSizePreset, dynamicIslandMode: Bool) -> CGRect {
        let size = panelCanvasSize(for: preset, in: screenFrame, dynamicIslandMode: dynamicIslandMode)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func isDynamicIslandMode(for screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top <= 0
    }

    private static func maxAllowedOpenWidth(in screenFrame: CGRect) -> CGFloat {
        max(screenFrame.width - maxWidthInset, 400)
    }

    private static func clampedClosedSize(_ size: CGSize, in screenFrame: CGRect) -> CGSize {
        let maximumWidth = max(80, screenFrame.width - horizontalMargin * 2)
        let maximumHeight = max(24, min(closedFallbackHeight, screenFrame.height * 0.12))
        return CGSize(
            width: min(max(size.width, 80), maximumWidth),
            height: min(max(size.height, 24), maximumHeight)
        )
    }
}
