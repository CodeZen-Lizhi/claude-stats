import Foundation
import Testing
@testable import ClaudeStats

@Suite("Preferences")
@MainActor
struct PreferencesTests {
    @Test("Floating tab defaults are enabled and right-docked")
    func floatingTabDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.floatingTabEnabled == true)
        #expect(prefs.floatingTabEdge == .right)
        #expect(prefs.floatingTabAnchor == 0.5)
    }

    @Test("Main window opens on launch by default")
    func mainWindowLaunchDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.openMainWindowOnLaunch == true)
    }

    @Test("Main window launch preference persists")
    func mainWindowLaunchPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.openMainWindowOnLaunch = false

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.openMainWindowOnLaunch == false)
    }

    @Test("Floating tab preferences persist")
    func floatingTabPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.floatingTabEnabled = false
        prefs.floatingTabEdge = .top
        prefs.floatingTabAnchor = 0.25

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.floatingTabEnabled == false)
        #expect(reloaded.floatingTabEdge == .top)
        #expect(reloaded.floatingTabAnchor == 0.25)
    }

    @Test("Invalid stored floating edge falls back safely")
    func invalidFloatingEdgeFallsBack() {
        let defaults = makeDefaults()
        defaults.set("sideways", forKey: "floatingTabEdge")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.floatingTabEdge == .right)
    }

    @Test("Detail panel boundary falloff defaults to enabled")
    func detailPanelBoundaryFalloffDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.detailPanelBoundaryFalloffEnabled == true)
    }

    @Test("Detail panel boundary falloff preference persists")
    func detailPanelBoundaryFalloffPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.detailPanelBoundaryFalloffEnabled = false

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.detailPanelBoundaryFalloffEnabled == false)
    }

    @Test("Main window sidebar width defaults and clamps")
    func mainWindowSidebarWidthDefaultsAndClamps() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.mainWindowSidebarWidth == Preferences.defaultMainWindowSidebarWidth)

        prefs.mainWindowSidebarWidth = 120
        #expect(prefs.mainWindowSidebarWidth == Preferences.mainWindowSidebarWidthRange.lowerBound)

        prefs.mainWindowSidebarWidth = 420
        #expect(prefs.mainWindowSidebarWidth == Preferences.mainWindowSidebarWidthRange.upperBound)

        defaults.set(Double.nan, forKey: "mainWindowSidebarWidth")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.mainWindowSidebarWidth == Preferences.defaultMainWindowSidebarWidth)
    }

    @Test("System Monitor defaults are off with balanced refresh and all modules")
    func systemMonitorDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.systemMonitorEnabled == false)
        #expect(prefs.systemMonitorRefreshRate == .threeSeconds)
        #expect(prefs.systemMonitorVisibleModules == SystemMonitorModule.defaultVisible)
    }

    @Test("System Monitor preferences persist and invalid refresh falls back")
    func systemMonitorPreferencesPersist() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.systemMonitorEnabled = true
        prefs.systemMonitorRefreshRate = .tenSeconds
        prefs.systemMonitorVisibleModules = [.cpu, .memory, .network]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.systemMonitorEnabled == true)
        #expect(reloaded.systemMonitorRefreshRate == .tenSeconds)
        #expect(reloaded.systemMonitorVisibleModules == [.cpu, .memory, .network])

        defaults.set("continuous", forKey: "systemMonitorRefreshRate")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.systemMonitorRefreshRate == .threeSeconds)
    }

    @Test("System Monitor empty module selection falls back to defaults")
    func systemMonitorEmptyModulesFallBack() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.systemMonitorVisibleModules = []

        #expect(prefs.systemMonitorVisibleModules == SystemMonitorModule.defaultVisible)
    }

    @Test("Git language stats scope defaults to HEAD")
    func gitStatsScopeDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.gitStatsScope == .head)
    }

    @Test("Git tracking defaults to visible")
    func gitTrackingDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.gitTrackingEnabled == true)
    }

    @Test("Git tracking visibility preference persists")
    func gitTrackingPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.gitTrackingEnabled = false

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.gitTrackingEnabled == false)
    }

    @Test("Git language stats scope preference persists")
    func gitStatsScopePersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.gitStatsScope = .workingTree

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.gitStatsScope == .workingTree)
    }

    @Test("Invalid git language stats scope falls back safely")
    func invalidGitStatsScopeFallsBack() {
        let defaults = makeDefaults()
        defaults.set("index", forKey: "gitStatsScope")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.gitStatsScope == .head)
    }

    @Test("Git diff block granularity defaults to fine")
    func gitDiffBlockGranularityDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.gitDiffBlockGranularity == .fine)
    }

    @Test("Git diff block granularity preference persists")
    func gitDiffBlockGranularityPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.gitDiffBlockGranularity = .coarse

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.gitDiffBlockGranularity == .coarse)
    }

    @Test("Invalid git diff block granularity falls back safely")
    func invalidGitDiffBlockGranularityFallsBack() {
        let defaults = makeDefaults()
        defaults.set("medium", forKey: "gitDiffBlockGranularity")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.gitDiffBlockGranularity == .fine)
    }

    @Test("Git workspace sources default to Codex")
    func gitWorkspaceSourcesDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.gitWorkspaceSourceIDs == [.codex])
    }

    @Test("Git workspace sources persist")
    func gitWorkspaceSourcesPersist() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.gitWorkspaceSourceIDs = [.codex, .cursor, .traeCN, .jetbrains]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.gitWorkspaceSourceIDs == [.codex, .cursor, .traeCN, .jetbrains])
        #expect(defaults.string(forKey: "gitWorkspaceSourceIDs") == "codex,cursor,traeCN,jetbrains")
    }

    @Test("Empty git workspace sources fall back to defaults")
    func emptyGitWorkspaceSourcesFallBack() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.gitWorkspaceSourceIDs = []

        #expect(prefs.gitWorkspaceSourceIDs == [.codex])
    }

    @Test("Invalid stored git workspace sources fall back to defaults")
    func invalidGitWorkspaceSourcesFallBack() {
        let defaults = makeDefaults()
        defaults.set("claude,unknown", forKey: "gitWorkspaceSourceIDs")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.gitWorkspaceSourceIDs == [.codex])
    }

    @Test("Cost estimation mode defaults to API estimate")
    func costEstimationModeDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.costEstimationMode == .standardAPI)
    }

    @Test("Cost estimation mode persists and invalid values fall back")
    func costEstimationModePersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.costEstimationMode = .detailedBilling

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.costEstimationMode == .detailedBilling)

        defaults.set("invoice", forKey: "costEstimationMode")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.costEstimationMode == .standardAPI)
    }

    @Test("OpenAI Status preferences default to visible ChatGPT and Codex without alerts")
    func openAIStatusDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.openAIStatusVisibleGroupIDs == OpenAIStatusGroupCatalog.defaultVisibleGroupIDs)
        #expect(prefs.openAIStatusNotificationsEnabled == false)
        #expect(prefs.openAIStatusLastNotificationFingerprint == "")
    }

    @Test("OpenAI Status preferences persist and empty visible groups fall back")
    func openAIStatusPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.openAIStatusVisibleGroupIDs = [OpenAIStatusGroupCatalog.apisID]
        prefs.openAIStatusNotificationsEnabled = true
        prefs.openAIStatusLastNotificationFingerprint = "group:degraded"

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.openAIStatusVisibleGroupIDs == [OpenAIStatusGroupCatalog.apisID])
        #expect(reloaded.openAIStatusNotificationsEnabled == true)
        #expect(reloaded.openAIStatusLastNotificationFingerprint == "group:degraded")

        reloaded.openAIStatusVisibleGroupIDs = []
        #expect(reloaded.openAIStatusVisibleGroupIDs == OpenAIStatusGroupCatalog.defaultVisibleGroupIDs)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.codexstats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
