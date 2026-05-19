import AppKit
import AtollEmbed
import Observation
import SwiftUI

@MainActor
final class NotchIslandController {
    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private var panels: [NSScreen: NSPanel] = [:]
    private var bridges: [NSScreen: AtollIslandRuntimeBridge] = [:]
    private var screenObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private let shortcutMonitor = NotchIslandShortcutMonitor()
    private var isStarted = false
    private var windowsHiddenForLock = false

    #if DEBUG
    var activePanelCountForTesting: Int { panels.count }
    #endif

    func start(environment: AppEnvironment) {
        guard !isStarted else { return }
        isStarted = true
        self.environment = environment
        self.preferences = environment.preferences
        observePreferences()
        observeScreenChanges()
        observeLockState()
        syncWithPreferences()
    }

    func stop() {
        closePanels()
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
                self?.syncWithPreferences()
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
                self?.closePanels()
                self?.syncWithPreferences()
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

    private func syncWithPreferences() {
        guard let environment, let preferences else { return }
        syncShortcutMonitor()
        guard preferences.notchIslandEnabled else {
            closePanels()
            return
        }

        let targetScreens = screens(for: preferences.notchIslandDisplayMode)
        let targetSet = Set(targetScreens)
        let staleScreens = panels.keys.filter { !targetSet.contains($0) }
        for screen in staleScreens {
            bridges[screen]?.stop()
            bridges.removeValue(forKey: screen)
            panels[screen]?.close()
            panels.removeValue(forKey: screen)
        }

        for screen in targetScreens {
            ensurePanel(on: screen, environment: environment)
        }
        let configuration = atollConfiguration(for: preferences)
        for bridge in bridges.values {
            bridge.update(configuration: configuration)
            bridge.refreshWindowFrame(animated: false, force: true)
        }
    }

    private func ensurePanel(on screen: NSScreen, environment: AppEnvironment) {
        guard panels[screen] == nil, let preferences else { return }
        let configuration = atollConfiguration(for: preferences)
        let frame = AtollIslandSizing.frame(for: screen, configuration: configuration)
        let panel = AtollIslandWindowFactory.makeWindow(frame: frame)

        let bridge = AtollIslandRuntimeBridge(
            screenName: screen.localizedName,
            configuration: configuration,
            settingsOpener: {
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: SettingsSection.notchIsland)
            }
        )
        bridge.attach(window: panel, screen: screen)

        let rootView = AtollIslandHostView(bridge: bridge)
            .environment(environment)

        let hostingView = NotchIslandHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panels[screen] = panel
        bridges[screen] = bridge
        panel.orderFrontRegardless()
    }

    private func syncShortcutMonitor() {
        guard let preferences, preferences.notchIslandShortcutEnabled else {
            shortcutMonitor.stop()
            return
        }
        guard !shortcutMonitor.isRunning else { return }
        shortcutMonitor.start { [weak self] in
            self?.toggleIslandOpen()
        }
    }

    private func toggleIslandOpen() {
        let mouse = NSEvent.mouseLocation
        let bridge = bridges.first { screen, _ in
            screen.frame.contains(mouse)
        }?.value ?? bridges.values.first
        bridge?.toggleOpen()
    }

    private func closePanels() {
        for bridge in bridges.values {
            bridge.stop()
        }
        for panel in panels.values {
            panel.close()
        }
        bridges.removeAll()
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
        for (screen, panel) in panels {
            bridges[screen]?.refreshWindowFrame(animated: false, force: true)
            panel.orderFrontRegardless()
        }
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

    private func atollConfiguration(for preferences: Preferences) -> AtollIslandConfiguration {
        AtollIslandConfiguration(
            enabledFeatures: Set(preferences.notchIslandEnabledModules.map(\.atollFeature)),
            openNotchWidth: AtollNotchGeometry.openWidth(for: preferences.notchIslandSizePreset),
            openOnHover: preferences.notchIslandHoverExpansionEnabled,
            showOnAllDisplays: preferences.notchIslandDisplayMode == .allDisplays,
            statsUpdateInterval: atollStatsUpdateInterval(for: preferences.systemMonitorRefreshRate)
        )
    }

    private func atollStatsUpdateInterval(for refreshRate: SystemMonitorRefreshRate) -> TimeInterval {
        switch refreshRate {
        case .off: 3
        case .oneSecond: 1
        case .threeSeconds: 3
        case .tenSeconds: 10
        case .thirtySeconds: 30
        }
    }
}

private extension NotchIslandModule {
    var atollFeature: AtollIslandFeature {
        switch self {
        case .media: .media
        case .stats: .stats
        case .timer: .timer
        case .clipboard: .clipboard
        case .colorPicker: .colorPicker
        case .calendar: .calendar
        case .shelf: .shelf
        case .privacy: .privacy
        case .recording: .recording
        case .focus: .focus
        case .battery: .battery
        case .bluetooth: .bluetooth
        case .downloads: .downloads
        case .osd: .osd
        case .lockScreenWidgets: .lockScreenWidgets
        case .extensionBridge: .extensionBridge
        case .screenAssistant: .screenAssistant
        case .terminal: .terminal
        }
    }
}

private final class NotchIslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
