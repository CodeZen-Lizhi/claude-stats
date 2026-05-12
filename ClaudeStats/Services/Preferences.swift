import Foundation
import Observation

/// What the menu-bar status item shows.
enum MenuBarMetric: String, CaseIterable, Sendable, Identifiable {
    case tokens
    case cost
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tokens: "Tokens"
        case .cost: "Cost"
        }
    }
}

/// Thin, observable wrapper over the handful of `UserDefaults` keys the app
/// uses. Writing a property persists it immediately.
@MainActor
@Observable
final class Preferences {
    var autoRefreshMinutes: Int {
        didSet { defaults.set(autoRefreshMinutes, forKey: Keys.autoRefreshMinutes) }
    }
    var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }
    var menuBarPeriod: StatsPeriod {
        didSet { defaults.set(menuBarPeriod.rawValue, forKey: Keys.menuBarPeriod) }
    }

    /// Which platforms the user has turned on. The switcher bar only appears
    /// when this has more than one entry; otherwise the panel shows the single
    /// enabled platform (and the original scanline strip). Always non-empty.
    var enabledProviders: Set<ProviderKind> {
        didSet {
            if enabledProviders.isEmpty { enabledProviders = [.claude] }   // re-fires didSet, persists below
            defaults.set(enabledProviders.map(\.rawValue).joined(separator: ","), forKey: Keys.enabledProviders)
            if !enabledProviders.contains(selectedProvider) {
                selectedProvider = orderedEnabledProviders.first ?? .claude
            }
        }
    }
    /// The platform currently being viewed. Always a member of ``enabledProviders``.
    var selectedProvider: ProviderKind {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider) }
    }
    /// When off, the app forgets ``selectedProvider`` on launch and starts on
    /// the first enabled platform.
    var rememberSelectedProvider: Bool {
        didSet { defaults.set(rememberSelectedProvider, forKey: Keys.rememberSelectedProvider) }
    }

    /// ``enabledProviders`` in canonical (``ProviderKind/allCases``) order.
    var orderedEnabledProviders: [ProviderKind] {
        ProviderKind.allCases.filter(enabledProviders.contains)
    }

    /// Opt-in to the AI activity analysis (reads macOS Screen Time; needs Full
    /// Disk Access). Off by default — the Activity tab only appears when on.
    var aiActivityAnalysisEnabled: Bool {
        didSet { defaults.set(aiActivityAnalysisEnabled, forKey: Keys.aiActivityAnalysisEnabled) }
    }
    /// Opt-in to git tracking — adds a view that correlates Claude usage with the
    /// commit activity of the repos you've used Claude in. Off by default.
    var gitTrackingEnabled: Bool {
        didSet { defaults.set(gitTrackingEnabled, forKey: Keys.gitTrackingEnabled) }
    }
    /// When git tracking is on: `true` opens the git view in its own window
    /// (button next to the panel title); `false` shows it as a pane in the panel.
    var gitOpensInWindow: Bool {
        didSet { defaults.set(gitOpensInWindow, forKey: Keys.gitOpensInWindow) }
    }
    /// Extra editor bundle ids the user added on top of ``IDEAppCatalog/defaults``.
    var ideBundleIDsAdded: [String] {
        didSet { defaults.set(ideBundleIDsAdded, forKey: Keys.ideBundleIDsAdded) }
    }
    /// Default editor bundle ids the user turned off.
    var ideBundleIDsRemoved: [String] {
        didSet { defaults.set(ideBundleIDsRemoved, forKey: Keys.ideBundleIDsRemoved) }
    }

    /// The editor bundle ids actually in effect for the analysis.
    var effectiveIDEBundleIDs: Set<String> {
        IDEAppCatalog.effectiveBundleIDs(added: ideBundleIDsAdded, removed: ideBundleIDsRemoved)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoRefreshMinutes = (defaults.object(forKey: Keys.autoRefreshMinutes) as? Int) ?? 5
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: Keys.menuBarMetric) ?? "") ?? .tokens
        menuBarPeriod = StatsPeriod(rawValue: defaults.string(forKey: Keys.menuBarPeriod) ?? "") ?? .allTime
        aiActivityAnalysisEnabled = defaults.bool(forKey: Keys.aiActivityAnalysisEnabled)
        gitTrackingEnabled = defaults.bool(forKey: Keys.gitTrackingEnabled)
        gitOpensInWindow = defaults.bool(forKey: Keys.gitOpensInWindow)
        ideBundleIDsAdded = defaults.stringArray(forKey: Keys.ideBundleIDsAdded) ?? []
        ideBundleIDsRemoved = defaults.stringArray(forKey: Keys.ideBundleIDsRemoved) ?? []

        let storedEnabled = (defaults.string(forKey: Keys.enabledProviders) ?? "")
            .split(separator: ",")
            .compactMap { ProviderKind(rawValue: String($0)) }
        let enabled = storedEnabled.isEmpty ? Set([ProviderKind.claude]) : Set(storedEnabled)
        let remember = (defaults.object(forKey: Keys.rememberSelectedProvider) as? Bool) ?? true
        let storedSelected = ProviderKind(rawValue: defaults.string(forKey: Keys.selectedProvider) ?? "")
        let firstEnabled = ProviderKind.allCases.first(where: enabled.contains) ?? .claude

        enabledProviders = enabled
        rememberSelectedProvider = remember
        if remember, let s = storedSelected, enabled.contains(s) {
            selectedProvider = s
        } else {
            selectedProvider = firstEnabled
        }
    }

    private enum Keys {
        static let autoRefreshMinutes = "autoRefreshMinutes"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarPeriod = "menuBarPeriod"
        static let aiActivityAnalysisEnabled = "aiActivityAnalysisEnabled"
        static let gitTrackingEnabled = "gitTrackingEnabled"
        static let gitOpensInWindow = "gitOpensInWindow"
        static let ideBundleIDsAdded = "ideBundleIDsAdded"
        static let ideBundleIDsRemoved = "ideBundleIDsRemoved"
        static let enabledProviders = "enabledProviders"
        static let selectedProvider = "selectedProvider"
        static let rememberSelectedProvider = "rememberSelectedProvider"
    }
}
