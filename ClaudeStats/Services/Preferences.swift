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

    /// Opt-in to the AI activity analysis (reads macOS Screen Time; needs Full
    /// Disk Access). Off by default — the Activity tab only appears when on.
    var aiActivityAnalysisEnabled: Bool {
        didSet { defaults.set(aiActivityAnalysisEnabled, forKey: Keys.aiActivityAnalysisEnabled) }
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
        ideBundleIDsAdded = defaults.stringArray(forKey: Keys.ideBundleIDsAdded) ?? []
        ideBundleIDsRemoved = defaults.stringArray(forKey: Keys.ideBundleIDsRemoved) ?? []
    }

    private enum Keys {
        static let autoRefreshMinutes = "autoRefreshMinutes"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarPeriod = "menuBarPeriod"
        static let aiActivityAnalysisEnabled = "aiActivityAnalysisEnabled"
        static let ideBundleIDsAdded = "ideBundleIDsAdded"
        static let ideBundleIDsRemoved = "ideBundleIDsRemoved"
    }
}
