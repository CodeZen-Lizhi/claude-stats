import AppKit
import Observation
import SwiftUI

@MainActor
final class NotchIslandController {
    let runtime = NotchIslandRuntime()

    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private var panels: [NSScreen: NotchIslandPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private let shortcutMonitor = NotchIslandShortcutMonitor()
    private var isStarted = false
    private var windowsHiddenForLock = false

    func start(environment: AppEnvironment) {
        guard !isStarted else { return }
        isStarted = true
        self.environment = environment
        self.preferences = environment.preferences
        observePreferences()
        observeScreenChanges()
        observeLockState()
        syncWithPreferences(animated: false)
    }

    func stop() {
        closePanels()
        runtime.stopAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
        shortcutMonitor.stop()
        screenObserver = nil
        lockObserver = nil
        unlockObserver = nil
        isStarted = false
    }

    private func observePreferences() {
        guard let preferences else { return }
        withObservationTracking {
            _ = preferences.notchIslandEnabled
            _ = preferences.notchIslandDisplayMode
            _ = preferences.notchIslandSizePreset
            _ = preferences.notchIslandHoverExpansionEnabled
            _ = preferences.notchIslandShortcutEnabled
            _ = preferences.notchIslandEnabledModules
            _ = preferences.systemMonitorRefreshRate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncWithPreferences(animated: true)
                self?.observePreferences()
            }
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncWithPreferences(animated: true)
            }
        }
    }

    private func observeLockState() {
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hidePanelsForLock()
            }
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restorePanelsAfterLock()
            }
        }
    }

    private func syncWithPreferences(animated: Bool) {
        guard let environment, let preferences else { return }
        syncShortcutMonitor()
        guard preferences.notchIslandEnabled else {
            closePanels()
            runtime.stopAll()
            return
        }

        runtime.configure(
            enabledModules: preferences.notchIslandEnabledModules,
            statsRefreshRate: preferences.systemMonitorRefreshRate
        )

        let targetScreens = screens(for: preferences.notchIslandDisplayMode)
        let targetSet = Set(targetScreens)
        let staleScreens = panels.keys.filter { !targetSet.contains($0) }
        for screen in staleScreens {
            panels[screen]?.orderOut(nil)
            panels.removeValue(forKey: screen)
        }

        for screen in targetScreens {
            ensurePanel(on: screen, environment: environment)
        }
        updatePanelFrames(animated: animated)
    }

    private func ensurePanel(on screen: NSScreen, environment: AppEnvironment) {
        guard panels[screen] == nil, let preferences else { return }
        let frame = NotchIslandLayoutPolicy.frame(
            in: screen.frame,
            preset: preferences.notchIslandSizePreset,
            expanded: runtime.isExpanded
        )
        let panel = NotchIslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.title = "Claude Stats Notch Island"
        panel.acceptsMouseMovedEvents = true

        let rootView = NotchIslandRootView(
            runtime: runtime,
            onExpansionChanged: { [weak self] in
                self?.updatePanelFrames(animated: true)
            }
        )
        .environment(environment)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panels[screen] = panel
        panel.orderFrontRegardless()
    }

    private func updatePanelFrames(animated: Bool) {
        guard let preferences else { return }
        for (screen, panel) in panels {
            let frame = NotchIslandLayoutPolicy.frame(
                in: screen.frame,
                preset: preferences.notchIslandSizePreset,
                expanded: runtime.isExpanded
            )
            guard panel.frame != frame else { continue }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
    }

    private func syncShortcutMonitor() {
        guard let preferences, preferences.notchIslandShortcutEnabled else {
            shortcutMonitor.stop()
            return
        }
        guard !shortcutMonitor.isRunning else { return }
        shortcutMonitor.start { [weak self] in
            self?.toggleIslandVisibility()
        }
    }

    private func toggleIslandVisibility() {
        guard let preferences else { return }
        preferences.notchIslandEnabled.toggle()
        syncWithPreferences(animated: true)
    }

    private func closePanels() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
        windowsHiddenForLock = false
    }

    private func hidePanelsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    private func restorePanelsAfterLock() {
        guard windowsHiddenForLock else { return }
        windowsHiddenForLock = false
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
        updatePanelFrames(animated: false)
    }

    private func screens(for mode: NotchIslandDisplayMode) -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        switch mode {
        case .primaryDisplay:
            return [NSScreen.main ?? screens[0]]
        case .pointerDisplay:
            let mouse = NSEvent.mouseLocation
            return [screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens[0]]
        case .allDisplays:
            return screens
        }
    }
}

private final class NotchIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
