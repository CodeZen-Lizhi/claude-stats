import Foundation
import GhosttyEmbed
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
    let updater = UpdaterController()
    let floatingStatsPanel = FloatingStatsPanelController()
    let terminalStore: EmbeddedTerminalStore
    /// View models live in the environment so the Settings window and the
    /// individual pages can share state — and so the VMs persist across
    /// main-window open/close cycles (reopening doesn't refire a fetch).
    let dashboard: DashboardViewModel
    let gitActivity: GitActivityViewModel
    let github = GitHubViewModel()
    let leaderboards: LeaderboardSyncViewModel
    let configurationProfiles: ConfigurationProfilesViewModel
    let apiProviders: APIProviderSwitcherViewModel
    let cliEnvironment: CLIEnvironmentViewModel

    init(
        pricing: ModelPricing,
        preferences: Preferences,
        providerRegistry: ProviderRegistry,
        store: SessionStore,
        terminalStore: EmbeddedTerminalStore = EmbeddedTerminalStore(),
        cliEnvironment: CLIEnvironmentViewModel = CLIEnvironmentViewModel()
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.providerRegistry = providerRegistry
        self.store = store
        self.terminalStore = terminalStore
        self.cliEnvironment = cliEnvironment
        self.dashboard = DashboardViewModel(pricing: pricing)
        self.gitActivity = GitActivityViewModel()
        self.leaderboards = LeaderboardSyncViewModel(preferences: preferences, store: store)
        self.configurationProfiles = ConfigurationProfilesViewModel(registry: providerRegistry)
        self.apiProviders = APIProviderSwitcherViewModel()
    }

    convenience init() {
        self.init(terminalStore: EmbeddedTerminalStore())
    }

    convenience init(terminalStore: EmbeddedTerminalStore) {
        let pricing = ModelPricing.loadDefault()
        let registry = ProviderRegistry(pricing: pricing)
        self.init(
            pricing: pricing,
            preferences: Preferences(),
            providerRegistry: registry,
            store: SessionStore(registry: registry, pricing: pricing),
            terminalStore: terminalStore
        )
    }

    /// Kick off the first scan and the periodic refresh. Call once at launch.
    func start() {
        Task {
            await apiProviders.loadIfNeeded(keyStorageMode: preferences.apiProviderKeyStorageMode)
            await configurationProfiles.loadIfNeeded()
            await store.refresh()
            leaderboards.start()
        }
        applyAutoRefreshSetting()
        updater.start()
        floatingStatsPanel.start(environment: self)
    }

    func applyAutoRefreshSetting() {
        store.startAutoRefresh(every: TimeInterval(preferences.autoRefreshMinutes) * 60)
    }
}
