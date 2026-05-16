import CoreGraphics
import Foundation

/// Pure drag math for the floating panel. AppKit screen coordinates use the
/// same bottom-left origin as global `NSWindow` frames, so y deltas are not
/// inverted.
enum FloatingPanelDragMotion {
    static let defaultActivationDistance: CGFloat = 22

    static func delta(from startMouse: CGPoint, to currentMouse: CGPoint) -> CGSize {
        CGSize(width: currentMouse.x - startMouse.x, height: currentMouse.y - startMouse.y)
    }

    static func frame(startFrame: CGRect, startMouse: CGPoint, currentMouse: CGPoint) -> CGRect {
        let movement = delta(from: startMouse, to: currentMouse)
        return startFrame.offsetBy(dx: movement.width, dy: movement.height)
    }

    static func activatedFrame(
        startFrame: CGRect,
        startMouse: CGPoint,
        currentMouse: CGPoint,
        activationDistance: CGFloat = defaultActivationDistance
    ) -> CGRect? {
        let movement = delta(from: startMouse, to: currentMouse)
        guard movement.distance >= activationDistance else { return nil }
        return startFrame.offsetBy(dx: movement.width, dy: movement.height)
    }
}

private extension CGSize {
    var distance: CGFloat {
        hypot(width, height)
    }
}
