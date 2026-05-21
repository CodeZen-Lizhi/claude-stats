import AppKit
import Combine
import Defaults
import Foundation

@MainActor
public final class AtollIslandRuntimeBridge {
    private var configuration: AtollIslandConfiguration
    private let screenName: String?
    private let screenID: String?
    private let settingsOpener: () -> Void
    private let viewModel: DynamicIslandViewModel
    private weak var attachedWindow: NSWindow?
    private weak var attachedScreen: NSScreen?
    private var sizingCancellables = Set<AnyCancellable>()
    private var didStart = false

    public init(
        screenName: String?,
        screenID: String? = nil,
        configuration: AtollIslandConfiguration,
        settingsOpener: @escaping () -> Void
    ) {
        self.screenName = screenName
        self.screenID = screenID
        self.configuration = configuration
        self.settingsOpener = settingsOpener
        AtollDefaultsBridge.sync(configuration)
        AtollSettingsRouter.openSettings = settingsOpener

        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.firstLaunch = false
        coordinator.alwaysShowTabs = true
        coordinator.openLastTabByDefault = false

        viewModel = DynamicIslandViewModel(screen: screenName, screenID: screenID)
    }

    func configurePrimaryRuntimeContext() {
        guard let screenName else { return }
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.selectedScreen = screenName
        coordinator.preferredScreen = screenName
    }

    func configureLockScreenManagers() {
        LockScreenLiveActivityWindowManager.shared.configure(viewModel: viewModel)
        LockScreenManager.shared.configure(viewModel: viewModel)
    }

    func closeForLockScreen() {
        viewModel.closeForLockScreen()
    }

    func makeContentView() -> ContentView {
        ContentView()
    }

    func environmentViewModel() -> DynamicIslandViewModel {
        viewModel
    }

    func environmentWebcamManager() -> WebcamManager {
        WebcamManager.shared
    }

    public func attach(window: NSWindow, screen: NSScreen) {
        attachedWindow = window
        attachedScreen = screen
        AppDelegate.shared?.register(window: window, viewModel: viewModel, for: screen)
        ensureWindowSize(animated: false, force: true)
    }

    public func update(configuration: AtollIslandConfiguration) {
        self.configuration = configuration
        AtollDefaultsBridge.sync(configuration)
        AtollSettingsRouter.openSettings = settingsOpener
        ensureValidCurrentTab()
        ensureWindowSize(animated: false, force: true)
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        AtollDefaultsBridge.sync(configuration)
        AtollSettingsRouter.openSettings = settingsOpener
        ensureValidCurrentTab()
        startWindowSizingObservers()
        ensureWindowSize(animated: false, force: true)
    }

    public func stop() {
        didStart = false
        sizingCancellables.removeAll()

        if let attachedScreen {
            AppDelegate.shared?.unregister(screen: attachedScreen)
        }
        attachedWindow = nil
        attachedScreen = nil
    }

    public func open() {
        viewModel.open()
    }

    public func close() {
        viewModel.close()
    }

    public func toggleOpen() {
        switch viewModel.notchState {
        case .closed:
            viewModel.open()
        case .open:
            viewModel.close()
        }
    }

    public func refreshWindowFrame(animated: Bool = false, force: Bool = true) {
        ensureWindowSize(animated: animated, force: force)
    }

    private func startWindowSizingObservers() {
        guard sizingCancellables.isEmpty else { return }
        let coordinator = DynamicIslandViewCoordinator.shared

        coordinator.$currentView
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.ensureWindowSize(animated: false, force: true)
                }
            }
            .store(in: &sizingCancellables)

        coordinator.$notesLayoutState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.ensureWindowSize(animated: false, force: true)
                }
            }
            .store(in: &sizingCancellables)

        let defaultChanges: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.openNotchWidth, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableStatsFeature, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showCpuGraph, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showMemoryGraph, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showGpuGraph, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showNetworkGraph, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showDiskGraph, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTerminalFeature, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.terminalMaxHeightFraction, options: []).map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(defaultChanges)
            .debounce(for: .milliseconds(40), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.ensureWindowSize(animated: false, force: true)
                }
            }
            .store(in: &sizingCancellables)
    }

    private func ensureWindowSize(animated: Bool, force: Bool) {
        guard attachedWindow != nil else { return }
        let size = AtollIslandSizing.requiredContentSize(for: attachedScreen)
        AppDelegate.shared?.ensureWindowSize(size, animated: animated, force: force)
    }

    private func ensureValidCurrentTab() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let features = configuration.enabledFeatures

        if features.contains(.media) || features.contains(.calendar) {
            coordinator.currentView = .home
        } else if features.contains(.shelf) {
            coordinator.currentView = .shelf
        } else if features.contains(.timer) {
            coordinator.currentView = .timer
        } else if features.contains(.stats) {
            coordinator.currentView = .stats
        } else if features.contains(.clipboard) {
            coordinator.currentView = .notes
        } else if features.contains(.terminal) {
            coordinator.currentView = .terminal
        } else {
            coordinator.currentView = .home
        }
    }

}

@MainActor
public final class AtollIslandRuntimeServiceOwner {
    private var configuration: AtollIslandConfiguration?
    private weak var primaryBridge: AtollIslandRuntimeBridge?
    private var didStart = false

    public init() {}

    public func update(
        configuration: AtollIslandConfiguration,
        primaryBridge: AtollIslandRuntimeBridge?
    ) {
        self.configuration = configuration
        self.primaryBridge = primaryBridge
        AtollDefaultsBridge.sync(configuration)
        primaryBridge?.configurePrimaryRuntimeContext()
        didStart = true
        syncManagers()
    }

    public func stop() {
        didStart = false
        WebcamManager.shared.stopSession()
        StatsManager.shared.stopMonitoring()
        ClipboardManager.shared.stopMonitoring()
        PrivacyIndicatorManager.shared.stopMonitoring()
        ScreenRecordingManager.shared.stopMonitoring()
        DoNotDisturbManager.shared.stopMonitoring()
        BluetoothAudioManager.shared.stopMonitoring()
        ExtensionXPCServiceHost.shared.stop()
        ExtensionRPCServer.shared.stop()
        Task { @MainActor in
            await SystemHUDManager.shared.stop()
        }
        ScreenAssistantManager.shared.closePanels()
        hideLockScreenPresentation()
        primaryBridge?.closeForLockScreen()
        primaryBridge = nil
        configuration = nil
    }

    private func syncManagers() {
        guard didStart, let configuration else { return }
        let features = configuration.enabledFeatures

        if features.contains(.stats) {
            StatsManager.shared.startMonitoring()
        } else {
            StatsManager.shared.stopMonitoring()
        }

        if features.contains(.clipboard) {
            ClipboardManager.shared.startMonitoring()
        } else {
            ClipboardManager.shared.stopMonitoring()
        }

        if features.contains(.privacy) {
            PrivacyIndicatorManager.shared.startMonitoring()
        } else {
            PrivacyIndicatorManager.shared.stopMonitoring()
        }

        if features.contains(.recording) {
            ScreenRecordingManager.shared.startMonitoring()
        } else {
            ScreenRecordingManager.shared.stopMonitoring()
        }

        if features.contains(.focus) {
            DoNotDisturbManager.shared.startMonitoring()
        } else {
            DoNotDisturbManager.shared.stopMonitoring()
        }

        if features.contains(.bluetooth) {
            BluetoothAudioManager.shared.startMonitoring()
        } else {
            BluetoothAudioManager.shared.stopMonitoring()
        }

        if features.contains(.downloads) {
            _ = DownloadManager.shared
        }

        if features.contains(.calendar) {
            _ = ReminderLiveActivityManager.shared
        }

        if features.contains(.osd) {
            SystemHUDManager.shared.setup(coordinator: DynamicIslandViewCoordinator.shared)
        } else {
            Task { @MainActor in
                await SystemHUDManager.shared.stop()
            }
        }

        if features.contains(.lockScreenWidgets) {
            primaryBridge?.configureLockScreenManagers()
        } else {
            hideLockScreenPresentation()
        }

        if features.contains(.extensionBridge) {
            ExtensionXPCServiceHost.shared.start()
            ExtensionRPCServer.shared.start()
        } else {
            ExtensionXPCServiceHost.shared.stop()
            ExtensionRPCServer.shared.stop()
        }

        if !features.contains(.screenAssistant) {
            ScreenAssistantManager.shared.closePanels()
        }
    }

    private func hideLockScreenPresentation() {
        LockScreenPanelManager.shared.hidePanel()
        FullScreenArtworkWindowManager.shared.hide()
        LockScreenLiveActivityWindowManager.shared.hideImmediately()
        LockScreenWeatherManager.shared.hideWeatherWidget()
        LockScreenTimerWidgetPanelManager.shared.hide(animated: false)
        LockScreenReminderWidgetPanelManager.shared.hide()
        TimerControlWindowManager.shared.hide(animated: false)
        let coordinator = DynamicIslandViewCoordinator.shared
        if coordinator.expandingView.type == .lockScreen {
            coordinator.toggleExpandingView(status: false, type: .lockScreen)
        }
    }
}
