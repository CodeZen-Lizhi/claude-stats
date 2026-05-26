import Foundation
import Observation

/// What the menu-bar status item shows.
enum MenuBarMetric: String, CaseIterable, Sendable, Identifiable {
    case tokens
    case cost
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tokens: L10n.string("menu_bar.metric.tokens", defaultValue: "Tokens")
        case .cost: L10n.string("menu_bar.metric.cost", defaultValue: "Cost")
        }
    }
}

/// Thin, observable wrapper over the handful of `UserDefaults` keys the app
/// uses. Writing a property persists it immediately.
@MainActor
@Observable
final class Preferences {
    var appLanguagePreference: AppLanguagePreference {
        didSet {
            defaults.set(appLanguagePreference.rawValue, forKey: Keys.appLanguagePreference)
            appLanguagePreference.applyToAppleLanguages(defaults: defaults)
        }
    }
    var autoRefreshMinutes: Int {
        didSet { defaults.set(autoRefreshMinutes, forKey: Keys.autoRefreshMinutes) }
    }
    var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }
    var menuBarPeriod: StatsPeriod {
        didSet { defaults.set(menuBarPeriod.rawValue, forKey: Keys.menuBarPeriod) }
    }
    /// Whether token totals shown in the app (Usage stats, BY MODEL, sessions
    /// list) include `cache_read` tokens. On by default — `cache_read` is what
    /// Anthropic's API reports per turn, so excluding it disagrees with the
    /// Console. Off gives a "real flow-through" figure closer to billed
    /// (non-cached) traffic. ``cache_creation`` is always counted regardless;
    /// only the per-turn cache-read re-reporting is what this gates.
    var includeCacheInTokens: Bool {
        didSet { defaults.set(includeCacheInTokens, forKey: Keys.includeCacheInTokens) }
    }
    /// Which cost estimate the UI displays. The standard API mode is the
    /// stable baseline; detailed billing applies only billable details that
    /// transcripts expose explicitly.
    var costEstimationMode: CostEstimationMode {
        didSet { defaults.set(costEstimationMode.rawValue, forKey: Keys.costEstimationMode) }
    }
    /// Same setting, but specifically for the menu-bar status item. Independent
    /// so users can keep the app totals canonical while the menu bar shows a
    /// less inflated figure (or vice versa).
    var menuBarIncludesCache: Bool {
        didSet { defaults.set(menuBarIncludesCache, forKey: Keys.menuBarIncludesCache) }
    }
    /// Whether launching Codex Statistics should present the main window. On by
    /// default so double-clicking the app behaves like a normal windowed app.
    var openMainWindowOnLaunch: Bool {
        didSet { defaults.set(openMainWindowOnLaunch, forKey: Keys.openMainWindowOnLaunch) }
    }
    /// Optional floating edge tab used as a backup entry point when the macOS
    /// menu bar is crowded.
    var floatingTabEnabled: Bool {
        didSet { defaults.set(floatingTabEnabled, forKey: Keys.floatingTabEnabled) }
    }
    /// Last snapped edge for the floating tab. Kept out of Settings to keep the
    /// UI simple; dragging the tab updates it silently.
    var floatingTabEdge: FloatingPanelEdge {
        didSet { defaults.set(floatingTabEdge.rawValue, forKey: Keys.floatingTabEdge) }
    }
    /// Normalized position along ``floatingTabEdge``. 0 is minX/minY, 1 is
    /// maxX/maxY; geometry helpers clamp it so the tab remains visible.
    var floatingTabAnchor: Double {
        didSet { defaults.set(floatingTabAnchor, forKey: Keys.floatingTabAnchor) }
    }
    /// Camera-notch Dynamic Island surface adapted from Atoll. Off by default
    /// so the existing menu-bar and floating-tab entry points remain unchanged.
    var notchIslandEnabled: Bool {
        didSet { defaults.set(notchIslandEnabled, forKey: Keys.notchIslandEnabled) }
    }
    var notchIslandDisplayMode: NotchIslandDisplayMode {
        didSet { defaults.set(notchIslandDisplayMode.rawValue, forKey: Keys.notchIslandDisplayMode) }
    }
    var notchIslandSelectedScreenIDs: Set<String> {
        didSet {
            if notchIslandSelectedScreenIDs.isEmpty {
                notchIslandSelectedScreenIDs = NotchIslandScreenCatalog.defaultSelectedScreenIDs()
                return
            }
            defaults.set(
                notchIslandSelectedScreenIDs.sorted().joined(separator: ","),
                forKey: Keys.notchIslandSelectedScreenIDs
            )
        }
    }
    var notchIslandScreenStyles: [String: NotchIslandScreenStyle] {
        didSet {
            persistNotchIslandScreenStyles()
        }
    }
    var notchIslandSizePreset: NotchIslandSizePreset {
        didSet { defaults.set(notchIslandSizePreset.rawValue, forKey: Keys.notchIslandSizePreset) }
    }
    var notchIslandHoverExpansionEnabled: Bool {
        didSet { defaults.set(notchIslandHoverExpansionEnabled, forKey: Keys.notchIslandHoverExpansionEnabled) }
    }
    var notchIslandShortcutEnabled: Bool {
        didSet { defaults.set(notchIslandShortcutEnabled, forKey: Keys.notchIslandShortcutEnabled) }
    }
    var notchIslandEnabledModules: Set<NotchIslandModule> {
        didSet {
            if notchIslandEnabledModules.isEmpty {
                notchIslandEnabledModules = NotchIslandModule.defaultEnabled
            }
            defaults.set(
                notchIslandEnabledModules.map(\.rawValue).sorted().joined(separator: ","),
                forKey: Keys.notchIslandEnabledModules
            )
        }
    }
    var detailPanelBoundaryFalloffEnabled: Bool {
        didSet { defaults.set(detailPanelBoundaryFalloffEnabled, forKey: Keys.detailPanelBoundaryFalloffEnabled) }
    }
    var sessionsExpandedOnAppOpen: Bool {
        didSet { defaults.set(sessionsExpandedOnAppOpen, forKey: Keys.sessionsExpandedOnAppOpen) }
    }
    var systemMonitorEnabled: Bool {
        didSet { defaults.set(systemMonitorEnabled, forKey: Keys.systemMonitorEnabled) }
    }
    var systemMonitorRefreshRate: SystemMonitorRefreshRate {
        didSet { defaults.set(systemMonitorRefreshRate.rawValue, forKey: Keys.systemMonitorRefreshRate) }
    }
    var systemMonitorVisibleModules: Set<SystemMonitorModule> {
        didSet {
            if systemMonitorVisibleModules.isEmpty {
                systemMonitorVisibleModules = SystemMonitorModule.defaultVisible
            }
            defaults.set(
                systemMonitorVisibleModules.map(\.rawValue).sorted().joined(separator: ","),
                forKey: Keys.systemMonitorVisibleModules
            )
        }
    }

    /// Which platform is enabled. The app is Codex-only, so this remains
    /// normalized to a single value for compatibility with shared data paths.
    var enabledProviders: Set<ProviderKind> {
        didSet {
            if enabledProviders != [.codex] {
                enabledProviders = [.codex]
                return
            }
            defaults.set(ProviderKind.codex.rawValue, forKey: Keys.enabledProviders)
        }
    }
    /// The platform currently being viewed. Always a member of ``enabledProviders``.
    var selectedProvider: ProviderKind {
        didSet {
            if selectedProvider != .codex {
                selectedProvider = .codex
                return
            }
            defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider)
        }
    }
    /// Kept for compatibility with older defaults. Codex-only builds always
    /// normalize the selected provider to Codex.
    var rememberSelectedProvider: Bool {
        didSet { defaults.set(rememberSelectedProvider, forKey: Keys.rememberSelectedProvider) }
    }

    /// ``enabledProviders`` in canonical (``ProviderKind/allCases``) order.
    var orderedEnabledProviders: [ProviderKind] {
        [.codex]
    }

    /// Adds a view that correlates Codex usage with the commit activity of the
    /// repos you've used Codex in. On by default so the main Tools section keeps
    /// its primary workspace entry visible; users can still hide it from
    /// Settings > Features.
    var gitTrackingEnabled: Bool {
        didSet { defaults.set(gitTrackingEnabled, forKey: Keys.gitTrackingEnabled) }
    }
    /// When git tracking is on: `true` opens the git view in its own window
    /// (button next to the panel title); `false` shows it as a pane in the panel.
    var gitOpensInWindow: Bool {
        didSet { defaults.set(gitOpensInWindow, forKey: Keys.gitOpensInWindow) }
    }
    /// Sources whose remembered workspaces feed the Git view. Defaults to
    /// Codex sessions, with AI editor workspace histories opt-in.
    var gitWorkspaceSourceIDs: Set<GitWorkspaceSourceID> {
        didSet {
            let normalized = GitWorkspaceSourceCatalog.normalized(gitWorkspaceSourceIDs)
            guard normalized == gitWorkspaceSourceIDs else {
                gitWorkspaceSourceIDs = normalized
                return
            }
            defaults.set(
                GitWorkspaceSourceCatalog.storageString(for: normalized),
                forKey: Keys.gitWorkspaceSourceIDs
            )
        }
    }
    /// Which tree the repo language/SLOC inspector uses.
    var gitStatsScope: GitStatsScope {
        didSet { defaults.set(gitStatsScope.rawValue, forKey: Keys.gitStatsScope) }
    }
    /// How split diff panes group changed lines into colored blocks.
    var gitDiffBlockGranularity: GitDiffBlockGranularity {
        didSet { defaults.set(gitDiffBlockGranularity.rawValue, forKey: Keys.gitDiffBlockGranularity) }
    }
    /// Opt-in to comparing local activity against the GitHub contribution
    /// graph on the Dashboard. Off by default — the dashboard's GitHub panel
    /// only appears when this is on and a PAT is configured.
    var githubEnabled: Bool {
        didSet { defaults.set(githubEnabled, forKey: Keys.githubEnabled) }
    }
    /// Last known GitHub login, for the Dashboard / Settings status row.
    /// Empty when not connected. The PAT itself lives in the Keychain.
    var githubLogin: String {
        didSet { defaults.set(githubLogin, forKey: Keys.githubLogin) }
    }
    /// OpenAI Status product groups shown on the Dashboard and monitored for
    /// optional notifications. Defaults to ChatGPT and Codex.
    var openAIStatusVisibleGroupIDs: Set<String> {
        didSet {
            if openAIStatusVisibleGroupIDs.isEmpty {
                openAIStatusVisibleGroupIDs = OpenAIStatusGroupCatalog.defaultVisibleGroupIDs
            }
            defaults.set(openAIStatusVisibleGroupIDs.sorted().joined(separator: ","), forKey: Keys.openAIStatusVisibleGroupIDs)
        }
    }
    /// Opt-in to macOS notifications when one of the visible OpenAI Status
    /// product groups is not operational.
    var openAIStatusNotificationsEnabled: Bool {
        didSet { defaults.set(openAIStatusNotificationsEnabled, forKey: Keys.openAIStatusNotificationsEnabled) }
    }
    /// Last abnormal visible OpenAI Status notification sent. Stored so the app
    /// does not repeat the same alert across polling cycles or relaunches.
    var openAIStatusLastNotificationFingerprint: String {
        didSet { defaults.set(openAIStatusLastNotificationFingerprint, forKey: Keys.openAIStatusLastNotificationFingerprint) }
    }
    /// Which colour scheme the Overlap heatmap should use.
    var overlapPalette: OverlapPalette {
        didSet { defaults.set(overlapPalette.rawValue, forKey: Keys.overlapPalette) }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appLanguagePreference = AppLanguagePreference(rawValue: defaults.string(forKey: Keys.appLanguagePreference) ?? "") ?? .system
        autoRefreshMinutes = (defaults.object(forKey: Keys.autoRefreshMinutes) as? Int) ?? 5
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: Keys.menuBarMetric) ?? "") ?? .tokens
        menuBarPeriod = StatsPeriod(rawValue: defaults.string(forKey: Keys.menuBarPeriod) ?? "") ?? .allTime
        includeCacheInTokens = (defaults.object(forKey: Keys.includeCacheInTokens) as? Bool) ?? true
        costEstimationMode = CostEstimationMode(rawValue: defaults.string(forKey: Keys.costEstimationMode) ?? "") ?? .standardAPI
        menuBarIncludesCache = (defaults.object(forKey: Keys.menuBarIncludesCache) as? Bool) ?? true
        openMainWindowOnLaunch = (defaults.object(forKey: Keys.openMainWindowOnLaunch) as? Bool) ?? true
        floatingTabEnabled = (defaults.object(forKey: Keys.floatingTabEnabled) as? Bool) ?? true
        floatingTabEdge = FloatingPanelEdge(rawValue: defaults.string(forKey: Keys.floatingTabEdge) ?? "") ?? .right
        floatingTabAnchor = (defaults.object(forKey: Keys.floatingTabAnchor) as? Double) ?? 0.5
        notchIslandEnabled = defaults.bool(forKey: Keys.notchIslandEnabled)
        let legacyNotchDisplayMode = NotchIslandDisplayMode(rawValue: defaults.string(forKey: Keys.notchIslandDisplayMode) ?? "") ?? .primaryDisplay
        notchIslandDisplayMode = legacyNotchDisplayMode
        let storedNotchScreenIDsRaw = defaults.string(forKey: Keys.notchIslandSelectedScreenIDs) ?? ""
        let storedNotchScreenIDs = storedNotchScreenIDsRaw
            .split(separator: ",")
            .map { String($0) }
        if storedNotchScreenIDs.isEmpty {
            let migratedScreenIDs = NotchIslandScreenCatalog.defaultSelectedScreenIDs(for: legacyNotchDisplayMode)
            notchIslandSelectedScreenIDs = migratedScreenIDs
            defaults.set(migratedScreenIDs.sorted().joined(separator: ","), forKey: Keys.notchIslandSelectedScreenIDs)
        } else {
            notchIslandSelectedScreenIDs = Set(storedNotchScreenIDs)
        }
        notchIslandScreenStyles = Self.decodeNotchIslandScreenStyles(defaults.string(forKey: Keys.notchIslandScreenStyles))
        notchIslandSizePreset = NotchIslandSizePreset(rawValue: defaults.string(forKey: Keys.notchIslandSizePreset) ?? "") ?? .regular
        notchIslandHoverExpansionEnabled = (defaults.object(forKey: Keys.notchIslandHoverExpansionEnabled) as? Bool) ?? true
        notchIslandShortcutEnabled = (defaults.object(forKey: Keys.notchIslandShortcutEnabled) as? Bool) ?? true
        let storedNotchModules = (defaults.string(forKey: Keys.notchIslandEnabledModules) ?? "")
            .split(separator: ",")
            .compactMap { NotchIslandModule(rawValue: String($0)) }
        notchIslandEnabledModules = storedNotchModules.isEmpty
            ? NotchIslandModule.defaultEnabled
            : Set(storedNotchModules)
        detailPanelBoundaryFalloffEnabled = (defaults.object(forKey: Keys.detailPanelBoundaryFalloffEnabled) as? Bool) ?? true
        sessionsExpandedOnAppOpen = (defaults.object(forKey: Keys.sessionsExpandedOnAppOpen) as? Bool) ?? false
        systemMonitorEnabled = defaults.bool(forKey: Keys.systemMonitorEnabled)
        systemMonitorRefreshRate = SystemMonitorRefreshRate(rawValue: defaults.string(forKey: Keys.systemMonitorRefreshRate) ?? "") ?? .threeSeconds
        let storedSystemMonitorModules = (defaults.string(forKey: Keys.systemMonitorVisibleModules) ?? "")
            .split(separator: ",")
            .compactMap { SystemMonitorModule(rawValue: String($0)) }
        systemMonitorVisibleModules = storedSystemMonitorModules.isEmpty
            ? SystemMonitorModule.defaultVisible
            : Set(storedSystemMonitorModules)
        gitTrackingEnabled = (defaults.object(forKey: Keys.gitTrackingEnabled) as? Bool) ?? true
        gitOpensInWindow = defaults.bool(forKey: Keys.gitOpensInWindow)
        gitWorkspaceSourceIDs = GitWorkspaceSourceCatalog.decodeStoredSourceIDs(
            defaults.string(forKey: Keys.gitWorkspaceSourceIDs)
        )
        gitStatsScope = GitStatsScope(rawValue: defaults.string(forKey: Keys.gitStatsScope) ?? "") ?? .head
        gitDiffBlockGranularity = GitDiffBlockGranularity(
            rawValue: defaults.string(forKey: Keys.gitDiffBlockGranularity) ?? ""
        ) ?? .fine
        githubEnabled = defaults.bool(forKey: Keys.githubEnabled)
        githubLogin = defaults.string(forKey: Keys.githubLogin) ?? ""
        let storedOpenAIStatusGroupIDs = (defaults.string(forKey: Keys.openAIStatusVisibleGroupIDs) ?? "")
            .split(separator: ",")
            .map { String($0) }
        openAIStatusVisibleGroupIDs = storedOpenAIStatusGroupIDs.isEmpty
            ? OpenAIStatusGroupCatalog.defaultVisibleGroupIDs
            : Set(storedOpenAIStatusGroupIDs)
        openAIStatusNotificationsEnabled = defaults.bool(forKey: Keys.openAIStatusNotificationsEnabled)
        openAIStatusLastNotificationFingerprint = defaults.string(forKey: Keys.openAIStatusLastNotificationFingerprint) ?? ""
        overlapPalette = OverlapPalette(rawValue: defaults.string(forKey: Keys.overlapPalette) ?? "") ?? .appCohesive

        let remember = (defaults.object(forKey: Keys.rememberSelectedProvider) as? Bool) ?? true

        enabledProviders = [.codex]
        rememberSelectedProvider = remember
        selectedProvider = .codex
        appLanguagePreference.applyToAppleLanguages(defaults: defaults)
    }

    private func persistNotchIslandScreenStyles() {
        let raw = notchIslandScreenStyles.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw),
              let json = String(data: data, encoding: .utf8) else {
            defaults.removeObject(forKey: Keys.notchIslandScreenStyles)
            return
        }
        defaults.set(json, forKey: Keys.notchIslandScreenStyles)
    }

    private static func decodeNotchIslandScreenStyles(_ raw: String?) -> [String: NotchIslandScreenStyle] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded.reduce(into: [:]) { result, pair in
            if let style = NotchIslandScreenStyle(rawValue: pair.value) {
                result[pair.key] = style
            }
        }
    }

    private enum Keys {
        static let appLanguagePreference = "appLanguagePreference"
        static let autoRefreshMinutes = "autoRefreshMinutes"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarPeriod = "menuBarPeriod"
        static let includeCacheInTokens = "includeCacheInTokens"
        static let costEstimationMode = "costEstimationMode"
        static let menuBarIncludesCache = "menuBarIncludesCache"
        static let openMainWindowOnLaunch = "openMainWindowOnLaunch"
        static let floatingTabEnabled = "floatingTabEnabled"
        static let floatingTabEdge = "floatingTabEdge"
        static let floatingTabAnchor = "floatingTabAnchor"
        static let notchIslandEnabled = "notchIslandEnabled"
        static let notchIslandDisplayMode = "notchIslandDisplayMode"
        static let notchIslandSelectedScreenIDs = "notchIslandSelectedScreenIDs"
        static let notchIslandScreenStyles = "notchIslandScreenStyles"
        static let notchIslandSizePreset = "notchIslandSizePreset"
        static let notchIslandHoverExpansionEnabled = "notchIslandHoverExpansionEnabled"
        static let notchIslandShortcutEnabled = "notchIslandShortcutEnabled"
        static let notchIslandEnabledModules = "notchIslandEnabledModules"
        static let detailPanelBoundaryFalloffEnabled = "detailPanelBoundaryFalloffEnabled"
        static let sessionsExpandedOnAppOpen = "sessionsExpandedOnAppOpen"
        static let systemMonitorEnabled = "systemMonitorEnabled"
        static let systemMonitorRefreshRate = "systemMonitorRefreshRate"
        static let systemMonitorVisibleModules = "systemMonitorVisibleModules"
        static let gitTrackingEnabled = "gitTrackingEnabled"
        static let gitOpensInWindow = "gitOpensInWindow"
        static let gitWorkspaceSourceIDs = "gitWorkspaceSourceIDs"
        static let gitStatsScope = "gitStatsScope"
        static let gitDiffBlockGranularity = "gitDiffBlockGranularity"
        static let enabledProviders = "enabledProviders"
        static let selectedProvider = "selectedProvider"
        static let rememberSelectedProvider = "rememberSelectedProvider"
        static let githubEnabled = "githubEnabled"
        static let githubLogin = "githubLogin"
        static let openAIStatusVisibleGroupIDs = "openAIStatusVisibleGroupIDs"
        static let openAIStatusNotificationsEnabled = "openAIStatusNotificationsEnabled"
        static let openAIStatusLastNotificationFingerprint = "openAIStatusLastNotificationFingerprint"
        static let overlapPalette = "overlapPalette"
    }
}
