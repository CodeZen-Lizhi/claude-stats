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

    @Test("Notch Island defaults are off with safe modules")
    func notchIslandDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.notchIslandEnabled == false)
        #expect(prefs.notchIslandDisplayMode == .primaryDisplay)
        #expect(prefs.notchIslandSizePreset == .regular)
        #expect(prefs.notchIslandHoverExpansionEnabled == true)
        #expect(prefs.notchIslandShortcutEnabled == true)
        #expect(prefs.notchIslandEnabledModules == NotchIslandModule.defaultEnabled)
    }

    @Test("Notch Island preferences persist and invalid values fall back")
    func notchIslandPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.notchIslandEnabled = true
        prefs.notchIslandDisplayMode = .allDisplays
        prefs.notchIslandSizePreset = .large
        prefs.notchIslandHoverExpansionEnabled = false
        prefs.notchIslandShortcutEnabled = false
        prefs.notchIslandEnabledModules = [.media, .timer, .clipboard]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.notchIslandEnabled == true)
        #expect(reloaded.notchIslandDisplayMode == .allDisplays)
        #expect(reloaded.notchIslandSizePreset == .large)
        #expect(reloaded.notchIslandHoverExpansionEnabled == false)
        #expect(reloaded.notchIslandShortcutEnabled == false)
        #expect(reloaded.notchIslandEnabledModules == [.media, .timer, .clipboard])

        defaults.set("floating", forKey: "notchIslandDisplayMode")
        defaults.set("massive", forKey: "notchIslandSizePreset")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.notchIslandDisplayMode == .primaryDisplay)
        #expect(invalid.notchIslandSizePreset == .regular)
    }

    @Test("Notch Island empty module selection falls back to safe defaults")
    func notchIslandEmptyModulesFallBack() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.notchIslandEnabledModules = []

        #expect(prefs.notchIslandEnabledModules == NotchIslandModule.defaultEnabled)
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

    @Test("Network traffic layout defaults to automatic with default breakpoint")
    func networkTrafficLayoutDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.networkTrafficLayoutMode == .automatic)
        #expect(prefs.networkTrafficAutoBreakpoint == NetworkTrafficLayoutConstants.defaultAutoBreakpoint)
    }

    @Test("Network traffic layout preferences persist and invalid mode falls back")
    func networkTrafficLayoutPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.networkTrafficLayoutMode = .sideBySide
        prefs.networkTrafficAutoBreakpoint = 1040

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.networkTrafficLayoutMode == .sideBySide)
        #expect(reloaded.networkTrafficAutoBreakpoint == 1040)

        defaults.set("diagonal", forKey: "networkTrafficLayoutMode")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.networkTrafficLayoutMode == .automatic)
    }

    @Test("Network traffic auto breakpoint clamps and resets")
    func networkTrafficAutoBreakpointClampsAndResets() {
        let defaults = makeDefaults()
        defaults.set(2_000.0, forKey: "networkTrafficAutoBreakpoint")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.networkTrafficAutoBreakpoint == NetworkTrafficLayoutConstants.maximumAutoBreakpoint)

        prefs.networkTrafficAutoBreakpoint = 100
        #expect(prefs.networkTrafficAutoBreakpoint == NetworkTrafficLayoutConstants.minimumAutoBreakpoint)

        prefs.resetNetworkTrafficAutoBreakpoint()
        #expect(prefs.networkTrafficAutoBreakpoint == NetworkTrafficLayoutConstants.defaultAutoBreakpoint)
    }

    @Test("Network traffic layout resolution follows mode and breakpoint")
    func networkTrafficLayoutResolution() {
        #expect(NetworkTrafficLayoutMode.automatic.resolved(width: 899, breakpoint: 900) == .stacked)
        #expect(NetworkTrafficLayoutMode.automatic.resolved(width: 900, breakpoint: 900) == .sideBySide)
        #expect(NetworkTrafficLayoutMode.stacked.resolved(width: 1600, breakpoint: 900) == .stacked)
        #expect(NetworkTrafficLayoutMode.sideBySide.resolved(width: 640, breakpoint: 1200) == .sideBySide)
    }

    @Test("Network proxy auto-enable defaults to off")
    func networkProxyAutoEnableDefault() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.networkAutoEnableSystemProxyOnStart == false)
    }

    @Test("Network proxy auto-enable preference persists")
    func networkProxyAutoEnablePersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.networkAutoEnableSystemProxyOnStart = true

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.networkAutoEnableSystemProxyOnStart == true)
    }

    @Test("Terminal appearance defaults use full chrome and fluid background")
    func terminalAppearanceDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.terminalChromeMode == .tabsAndStatus)
        #expect(prefs.terminalBackgroundStyle == .fluidGradient)
    }

    @Test("Terminal appearance preferences persist")
    func terminalAppearancePersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.terminalChromeMode = .statusOnly
        prefs.terminalBackgroundStyle = .solid

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.terminalChromeMode == .statusOnly)
        #expect(reloaded.terminalBackgroundStyle == .solid)
    }

    @Test("Invalid terminal appearance values fall back safely")
    func invalidTerminalAppearanceFallsBack() {
        let defaults = makeDefaults()
        defaults.set("floating", forKey: "terminalChromeMode")
        defaults.set("wallpaper", forKey: "terminalBackgroundStyle")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.terminalChromeMode == .tabsAndStatus)
        #expect(prefs.terminalBackgroundStyle == .fluidGradient)
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

    @Test("Claude Status preferences default to visible claude.ai and Claude Code without alerts")
    func claudeStatusDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.claudeStatusVisibleComponentIDs == ClaudeStatusComponentCatalog.defaultVisibleComponentIDs)
        #expect(prefs.claudeStatusNotificationsEnabled == false)
        #expect(prefs.claudeStatusLastNotificationFingerprint == "")
    }

    @Test("Claude Status preferences persist and empty visible components fall back")
    func claudeStatusPersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.claudeStatusVisibleComponentIDs = [ClaudeStatusComponentCatalog.claudeAPIID]
        prefs.claudeStatusNotificationsEnabled = true
        prefs.claudeStatusLastNotificationFingerprint = "component:degraded"

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.claudeStatusVisibleComponentIDs == [ClaudeStatusComponentCatalog.claudeAPIID])
        #expect(reloaded.claudeStatusNotificationsEnabled == true)
        #expect(reloaded.claudeStatusLastNotificationFingerprint == "component:degraded")

        reloaded.claudeStatusVisibleComponentIDs = []
        #expect(reloaded.claudeStatusVisibleComponentIDs == ClaudeStatusComponentCatalog.defaultVisibleComponentIDs)
    }

    @Test("Claude Desktop usage capture preferences default to visible-only manual-safe mode")
    func claudeDesktopUsageCaptureDefaults() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.claudeDesktopUsageAutoMode == .visibleOnly)
        #expect(prefs.claudeDesktopUsageTimedCaptureEnabled == false)
        #expect(prefs.claudeDesktopUsageTimedIntervalMinutes == 30)
    }

    @Test("Claude Desktop usage capture preferences persist and interval clamps")
    func claudeDesktopUsageCapturePersists() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.claudeDesktopUsageAutoMode = .off
        prefs.claudeDesktopUsageTimedCaptureEnabled = true
        prefs.claudeDesktopUsageTimedIntervalMinutes = 1

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.claudeDesktopUsageAutoMode == .off)
        #expect(reloaded.claudeDesktopUsageTimedCaptureEnabled == true)
        #expect(reloaded.claudeDesktopUsageTimedIntervalMinutes == 5)

        defaults.set("always", forKey: "claudeDesktopUsageAutoMode")
        defaults.set(999, forKey: "claudeDesktopUsageTimedIntervalMinutes")
        let invalid = Preferences(defaults: defaults)
        #expect(invalid.claudeDesktopUsageAutoMode == .visibleOnly)
        #expect(invalid.claudeDesktopUsageTimedIntervalMinutes == 240)
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

    @Test("Legacy IDE bundle preferences migrate to coding surfaces")
    func legacyIDEBundlePreferencesMigrate() {
        let defaults = makeDefaults()
        defaults.set(["com.example.LegacyEditor"], forKey: "ideBundleIDsAdded")
        defaults.set(["com.apple.dt.Xcode"], forKey: "ideBundleIDsRemoved")

        let prefs = Preferences(defaults: defaults)

        #expect(prefs.codingSurfaceBundleIDsAdded == ["com.example.LegacyEditor"])
        #expect(prefs.codingSurfaceBundleIDsRemoved == ["com.apple.dt.Xcode"])
        #expect(prefs.effectiveCodingSurfaceBundleIDs.contains("com.example.LegacyEditor"))
        #expect(!prefs.effectiveCodingSurfaceBundleIDs.contains("com.apple.dt.Xcode"))
        #expect(defaults.stringArray(forKey: "codingSurfaceBundleIDsAdded") == ["com.example.LegacyEditor"])
        #expect(defaults.stringArray(forKey: "codingSurfaceBundleIDsRemoved") == ["com.apple.dt.Xcode"])
    }

    @Test("CLI host bundle preferences persist")
    func cliHostBundlePreferencesPersist() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.cliHostBundleIDsAdded = ["com.example.Terminal"]
        prefs.cliHostBundleIDsRemoved = ["com.apple.Terminal"]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.cliHostBundleIDsAdded == ["com.example.Terminal"])
        #expect(reloaded.cliHostBundleIDsRemoved == ["com.apple.Terminal"])
        #expect(reloaded.effectiveCLIHostBundleIDs.contains("com.example.Terminal"))
        #expect(!reloaded.effectiveCLIHostBundleIDs.contains("com.apple.Terminal"))
        #expect(reloaded.effectiveCLIHostBundleIDs.contains("com.mitchellh.ghostty"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.claudestats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
