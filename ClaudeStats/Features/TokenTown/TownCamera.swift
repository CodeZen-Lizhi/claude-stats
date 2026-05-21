import Foundation

struct TownCameraViewport: Hashable, Sendable {
    var viewWidth: Double
    var viewHeight: Double
    var worldWidth: Double
    var worldHeight: Double

    var isValid: Bool {
        viewWidth > 1 && viewHeight > 1 && worldWidth > 1 && worldHeight > 1
    }
}

enum TownCameraMath {
    static let minScale = 1.0
    static let maxScale = 4.0

    static func normalized(_ camera: TownCameraState, viewport: TownCameraViewport) -> TownCameraState {
        guard viewport.isValid else {
            return TownCameraState(centerX: camera.centerX, centerY: camera.centerY, scale: clampedScale(camera.scale))
        }

        let scale = clampedScale(camera.scale)
        let centerX = camera.centerX ?? viewport.worldWidth / 2
        let centerY = camera.centerY ?? viewport.worldHeight / 2
        return clamped(
            TownCameraState(centerX: centerX, centerY: centerY, scale: scale),
            viewport: viewport
        )
    }

    static func zoomed(
        _ camera: TownCameraState,
        factor: Double,
        anchorX: Double,
        anchorY: Double,
        viewport: TownCameraViewport
    ) -> TownCameraState {
        let current = normalized(camera, viewport: viewport)
        let nextScale = clampedScale(current.scale * factor)
        guard viewport.isValid, nextScale != current.scale else {
            return current
        }

        let oldVisible = visibleWorldSize(for: current.scale, viewport: viewport)
        let nextVisible = visibleWorldSize(for: nextScale, viewport: viewport)
        let xRatio = nextVisible.width / oldVisible.width
        let yRatio = nextVisible.height / oldVisible.height
        let centerX = anchorX - (anchorX - (current.centerX ?? viewport.worldWidth / 2)) * xRatio
        let centerY = anchorY - (anchorY - (current.centerY ?? viewport.worldHeight / 2)) * yRatio

        return clamped(
            TownCameraState(centerX: centerX, centerY: centerY, scale: nextScale),
            viewport: viewport
        )
    }

    static func panned(
        _ camera: TownCameraState,
        deltaViewX: Double,
        deltaViewY: Double,
        viewport: TownCameraViewport
    ) -> TownCameraState {
        let current = normalized(camera, viewport: viewport)
        guard viewport.isValid else { return current }
        let visible = visibleWorldSize(for: current.scale, viewport: viewport)
        let worldPerViewX = visible.width / viewport.viewWidth
        let worldPerViewY = visible.height / viewport.viewHeight
        let centerX = (current.centerX ?? viewport.worldWidth / 2) - deltaViewX * worldPerViewX
        let centerY = (current.centerY ?? viewport.worldHeight / 2) - deltaViewY * worldPerViewY
        return clamped(
            TownCameraState(centerX: centerX, centerY: centerY, scale: current.scale),
            viewport: viewport
        )
    }

    static func visibleWorldSize(for scale: Double, viewport: TownCameraViewport) -> (width: Double, height: Double) {
        guard viewport.isValid else { return (viewport.viewWidth, viewport.viewHeight) }
        let baseScale = max(0.01, min(viewport.worldWidth / viewport.viewWidth, viewport.worldHeight / viewport.viewHeight))
        let cameraScale = baseScale / clampedScale(scale)
        return (
            width: viewport.viewWidth * cameraScale,
            height: viewport.viewHeight * cameraScale
        )
    }

    static func spriteKitCameraScale(for scale: Double, viewport: TownCameraViewport) -> Double {
        guard viewport.isValid else { return 1 / clampedScale(scale) }
        let baseScale = max(0.01, min(viewport.worldWidth / viewport.viewWidth, viewport.worldHeight / viewport.viewHeight))
        return baseScale / clampedScale(scale)
    }

    private static func clampedScale(_ scale: Double) -> Double {
        min(maxScale, max(minScale, scale))
    }

    private static func clamped(_ camera: TownCameraState, viewport: TownCameraViewport) -> TownCameraState {
        guard viewport.isValid else { return camera }
        let visible = visibleWorldSize(for: camera.scale, viewport: viewport)
        let centerX = clamp(
            camera.centerX ?? viewport.worldWidth / 2,
            lower: visible.width / 2,
            upper: viewport.worldWidth - visible.width / 2,
            fallback: viewport.worldWidth / 2
        )
        let centerY = clamp(
            camera.centerY ?? viewport.worldHeight / 2,
            lower: visible.height / 2,
            upper: viewport.worldHeight - visible.height / 2,
            fallback: viewport.worldHeight / 2
        )
        return TownCameraState(centerX: centerX, centerY: centerY, scale: clampedScale(camera.scale))
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double, fallback: Double) -> Double {
        guard lower <= upper else { return fallback }
        return min(upper, max(lower, value))
    }
}
