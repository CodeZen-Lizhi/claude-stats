import AtollEmbed
import Foundation
import Testing
@testable import ClaudeStats

@Suite("AtollIslandPreview")
@MainActor
struct AtollIslandPreviewTests {
    @Test("Every Notch Island settings tab can build a preview configuration")
    func everySettingsTabBuildsPreviewConfiguration() {
        let preferences = previewPreferences()
        let enabledTabs = Set(NotchIslandModule.allCases.map(\.previewTab))

        for tab in NotchIslandSettingsTab.allCases {
            let configuration = AtollIslandPreviewConfiguration(
                selectedTab: tab.previewTab,
                enabledTabs: enabledTabs,
                sizePreset: preferences.notchIslandSizePreset.previewSizePreset,
                isFeatureEnabled: preferences.notchIslandEnabled,
                hoverExpansionEnabled: preferences.notchIslandHoverExpansionEnabled,
                settings: AtollIslandPreviewSettings.current()
            )

            #expect(configuration.selectedTab == tab.previewTab)
            #expect(configuration.isSelectedTabEnabled)
            _ = AtollIslandPreviewView(configuration: configuration)
        }
    }

    @Test("Disabled feature and disabled modules stay renderable")
    func disabledStatesAreRenderable() {
        let settings = AtollIslandPreviewSettings.current()
        let disabledFeature = AtollIslandPreviewConfiguration(
            selectedTab: .stats,
            enabledTabs: [.stats],
            sizePreset: .regular,
            isFeatureEnabled: false,
            hoverExpansionEnabled: true,
            settings: settings
        )
        #expect(!disabledFeature.isSelectedTabEnabled)
        _ = AtollIslandPreviewView(configuration: disabledFeature)

        let disabledModule = AtollIslandPreviewConfiguration(
            selectedTab: .stats,
            enabledTabs: [],
            sizePreset: .regular,
            isFeatureEnabled: true,
            hoverExpansionEnabled: true,
            settings: settings
        )
        #expect(!disabledModule.isSelectedTabEnabled)
        _ = AtollIslandPreviewView(configuration: disabledModule)

        let alwaysAvailable = AtollIslandPreviewConfiguration(
            selectedTab: .appearance,
            enabledTabs: [],
            sizePreset: .regular,
            isFeatureEnabled: true,
            hoverExpansionEnabled: true,
            settings: settings
        )
        #expect(alwaysAvailable.isSelectedTabEnabled)
    }

    @Test("Size presets expose stable minimum preview widths")
    func sizePresetMinimumPreviewWidthsAreStable() {
        #expect(AtollIslandPreviewSizePreset.compact.minimumDisplayWidth == 584)
        #expect(AtollIslandPreviewSizePreset.regular.minimumDisplayWidth == 654)
        #expect(AtollIslandPreviewSizePreset.large.minimumDisplayWidth == 714)
    }

    @Test("Settings snapshot reflects bridge values")
    func settingsSnapshotReflectsBridgeValues() {
        let settingIDs = [
            "stats.showCpuGraph",
            "timer.timerProgressStyle",
            "downloads.selectedDownloadIndicatorStyle",
            "terminal.terminalFontSize",
            "terminal.terminalBackgroundColor"
        ]
        let originals = settingIDs.reduce(into: [String: AtollSettingValue]()) { result, id in
            result[id] = AtollSettingsBridge.value(for: id)
        }
        defer {
            for (id, value) in originals {
                _ = AtollSettingsBridge.setValue(value, for: id)
            }
        }

        let color = AtollSettingColor(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.9)
        #expect(AtollSettingsBridge.setValue(.bool(false), for: "stats.showCpuGraph"))
        #expect(AtollSettingsBridge.setValue(.string("Ring"), for: "timer.timerProgressStyle"))
        #expect(AtollSettingsBridge.setValue(.string("Circle"), for: "downloads.selectedDownloadIndicatorStyle"))
        #expect(AtollSettingsBridge.setValue(.double(18), for: "terminal.terminalFontSize"))
        #expect(AtollSettingsBridge.setValue(.color(color), for: "terminal.terminalBackgroundColor"))

        let snapshot = AtollIslandPreviewSettings.current()
        #expect(!snapshot.showCpuGraph)
        #expect(snapshot.timerProgressStyle == "Ring")
        #expect(snapshot.selectedDownloadIndicatorStyle == "Circle")
        #expect(snapshot.terminalFontSize == 18)
        #expect(snapshot.terminalBackgroundColor == color)
    }

    @Test("Sample data and fallback tab mapping are deterministic")
    func sampleDataAndFallbackAreDeterministic() {
        let first = AtollIslandPreviewSampleData.deterministic
        let second = AtollIslandPreviewSampleData.deterministic

        #expect(first == second)
        #expect(first.stats.map(\.id) == ["cpu", "memory", "gpu", "network", "disk"])
        #expect((AtollIslandPreviewTab(rawValue: "missing") ?? .island) == .island)
    }

    private func previewPreferences() -> Preferences {
        let suiteName = "AtollIslandPreviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = Preferences(defaults: defaults)
        preferences.notchIslandEnabled = true
        preferences.notchIslandSizePreset = .regular
        preferences.notchIslandHoverExpansionEnabled = true
        preferences.notchIslandEnabledModules = Set(NotchIslandModule.allCases)
        return preferences
    }
}
