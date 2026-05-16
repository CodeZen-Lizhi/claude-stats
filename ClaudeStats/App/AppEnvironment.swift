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
    let store: SessionStore
    let updater = UpdaterController()
    let floatingStatsPanel = FloatingStatsPanelController()
    let terminalStore: EmbeddedTerminalStore
    /// View models live in the environment so the Settings window and the
    /// individual pages can share state — and so the VMs persist across
    /// main-window open/close cycles (reopening doesn't refire a fetch).
    let dashboard: DashboardViewModel
    let github = GitHubViewModel()
    let leaderboards: LeaderboardSyncViewModel

    init(
        pricing: ModelPricing,
        preferences: Preferences,
        store: SessionStore,
        terminalStore: EmbeddedTerminalStore = EmbeddedTerminalStore()
    ) {
        self.pricing = pricing
        self.preferences = preferences
        self.store = store
        self.terminalStore = terminalStore
        self.dashboard = DashboardViewModel(pricing: pricing)
        self.leaderboards = LeaderboardSyncViewModel(preferences: preferences, store: store)
    }

    convenience init() {
        self.init(terminalStore: EmbeddedTerminalStore())
    }

    convenience init(terminalStore: EmbeddedTerminalStore) {
        let pricing = ModelPricing.loadDefault()
        self.init(
            pricing: pricing,
            preferences: Preferences(),
            store: SessionStore(registry: ProviderRegistry(pricing: pricing), pricing: pricing),
            terminalStore: terminalStore
        )
    }

    /// Kick off the first scan and the periodic refresh. Call once at launch.
    func start() {
        Task {
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
