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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.claudestats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
