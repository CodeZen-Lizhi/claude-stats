import Foundation
import Observation

/// Composition root. Constructs the pricing table, preferences, provider
/// registry, and the shared ``SessionStore``, then hands itself to the view
/// tree via `.environment(_:)`. Views read it with
/// `@Environment(AppEnvironment.self)`.
@MainActor
@Observable
final class AppEnvironment {
    let pricing: ModelPricing
    let preferences: Preferences
    let providerRegistry: ProviderRegistry
    let store: SessionStore
    let transcriptAnalysis: TranscriptAnalysisStore
    let updater = UpdaterController()
    let floatingStatsPanel = FloatingStatsPanelController()
    let notchIsland = NotchIslandController()
    /// View models live in the environment so the Settings window and the
    /// individual pages can share state — and so the VMs persist across
    /// main-window open/close cycles (reopening doesn't refire a fetch).
    let dashboard: DashboardViewModel
    let gitActivity: GitActivityViewModel
    let github = GitHubViewModel()
    let openAIStatus: OpenAIStatusViewModel
    let usageLimits: UsageLimitStore
    let configurationProfiles: ConfigurationProfilesViewModel
    let apiProviders: APIProviderSwitcherViewModel
    let cliEnvironment: CLIEnvironmentViewModel
    let aiConfigs: AIConfigsViewModel
    let skills: SkillsStore
    let systemMonitor: SystemMonitorViewModel
    let networkDebugger: NetworkDebuggerStore
    let ops: OpsStore

    init(
        pricing: ModelPricing,
        preferences: Preferences,
        providerRegistry: ProviderRegistry,
        store: SessionStore,
        usageLimits: UsageLimitStore? = nil,
        cliEnvironment: CLIEnvironmentViewModel = CLIEnvironmentViewModel(),
        systemMonitor: SystemMonitorViewModel = SystemMonitorViewModel(),
        networkDebugger: NetworkDebuggerStore? = nil,
        ops: OpsStore = OpsStore()
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.providerRegistry = providerRegistry
        self.store = store
        self.transcriptAnalysis = TranscriptAnalysisStore()
        self.cliEnvironment = cliEnvironment
        self.systemMonitor = systemMonitor
        self.networkDebugger = networkDebugger ?? NetworkDebuggerStore(preferences: preferences)
        self.ops = ops
        self.dashboard = DashboardViewModel(pricing: pricing)
        self.gitActivity = GitActivityViewModel()
        self.openAIStatus = OpenAIStatusViewModel(preferences: preferences)
        self.usageLimits = usageLimits ?? UsageLimitStore(registry: providerRegistry)
        self.configurationProfiles = ConfigurationProfilesViewModel(registry: providerRegistry)
        self.apiProviders = APIProviderSwitcherViewModel()
        self.aiConfigs = AIConfigsViewModel(scanner: AIConfigScanner(registry: providerRegistry))
        self.skills = SkillsStore()
    }

    convenience init() {
        let pricing = ModelPricing.loadDefault()
        let registry = ProviderRegistry(pricing: pricing)
        self.init(
            pricing: pricing,
            preferences: Preferences(),
            providerRegistry: registry,
            store: SessionStore(registry: registry, pricing: pricing)
        )
    }

    /// Kick off the first scan and the periodic refresh. Call once at launch.
    func start() {
        LegacyFeatureDataCleaner().cleanRemovedFeatureData()
        LaunchAtLogin.enableByDefaultIfNeeded()
        Task {
            await apiProviders.loadIfNeeded(keyStorageMode: preferences.apiProviderKeyStorageMode)
            await configurationProfiles.loadIfNeeded()
            await store.refresh()
        }
        openAIStatus.start()
        applyAutoRefreshSetting()
        updater.start()
        floatingStatsPanel.start(environment: self)
        if !Self.isRunningUnitTests {
            notchIsland.start(environment: self)
        }
    }

    func applyAutoRefreshSetting() {
        store.startAutoRefresh(every: TimeInterval(preferences.autoRefreshMinutes) * 60)
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
