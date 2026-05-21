import AppKit
import Defaults

@MainActor
final class AppDelegate: NSObject {
    static let shared: AppDelegate? = AppDelegate()

    private(set) var window: NSWindow?
    private(set) var windows: [NSScreen: NSWindow] = [:]
    private(set) var viewModels: [NSScreen: DynamicIslandViewModel] = [:]

    func register(window: NSWindow, viewModel: DynamicIslandViewModel, for screen: NSScreen) {
        windows[screen] = window
        viewModels[screen] = viewModel
        self.window = window
    }

    func unregister(screen: NSScreen) {
        windows.removeValue(forKey: screen)
        viewModels.removeValue(forKey: screen)
        if window?.screen == screen || window == nil {
            window = windows.values.first
        }
    }

    func ensureWindowSize(_ size: CGSize, animated: Bool, force: Bool = false) {
        guard size.width > 0, size.height > 0 else { return }

        if Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                resize(window, on: screen, to: adjustedSize(size, for: screen), animated: animated, force: force)
            }
        } else if let window {
            let screen = window.screen
                ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
            guard let screen else { return }
            resize(window, on: screen, to: adjustedSize(size, for: screen), animated: animated, force: force)
        }
    }

    private func adjustedSize(_ baseSize: CGSize, for screen: NSScreen) -> CGSize {
        guard shouldUseDynamicIslandMode(for: screen) else {
            return baseSize
        }

        return CGSize(
            width: baseSize.width + dynamicIslandShadowInset * 2,
            height: baseSize.height + dynamicIslandTopOffset
        )
    }

    private func resize(
        _ window: NSWindow,
        on screen: NSScreen,
        to size: CGSize,
        animated: Bool,
        force: Bool
    ) {
        let clampedWidth = min(size.width, screen.frame.width)
        let clampedHeight = min(size.height, screen.frame.height)
        let frame = NSRect(
            x: screen.frame.midX - clampedWidth / 2,
            y: screen.frame.maxY - clampedHeight,
            width: clampedWidth,
            height: clampedHeight
        )

        guard force || window.frame != frame else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}
