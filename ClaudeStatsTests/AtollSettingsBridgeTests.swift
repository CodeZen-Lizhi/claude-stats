import AtollEmbed
import Testing

@Suite("AtollSettingsBridge")
@MainActor
struct AtollSettingsBridgeTests {
    @Test("Every Notch Island settings tab exposes readable descriptors")
    func descriptorsExistForEveryTab() {
        for tab in AtollSettingsTabID.allCases {
            let groups = AtollSettingsBridge.groups(for: tab)
            #expect(!groups.isEmpty, "Missing groups for \(tab.rawValue)")

            let descriptors = groups.flatMap(\.settings)
            #expect(!descriptors.isEmpty, "Missing settings for \(tab.rawValue)")

            for descriptor in descriptors {
                #expect(AtollSettingsBridge.value(for: descriptor.id) != nil, "Unreadable setting \(descriptor.id)")
            }
        }
    }

    @Test("Bridge round-trips common setting value types")
    func valueRoundTrips() {
        let originals = [
            "stats.showCpuGraph",
            "stats.statsUpdateInterval",
            "clipboard.clipboardHistorySize",
            "terminal.terminalShellPath",
            "terminal.terminalBackgroundColor"
        ].reduce(into: [String: AtollSettingValue]()) { result, id in
            result[id] = AtollSettingsBridge.value(for: id)
        }
        defer {
            for (id, value) in originals {
                _ = AtollSettingsBridge.setValue(value, for: id)
            }
        }

        #expect(AtollSettingsBridge.setValue(.bool(false), for: "stats.showCpuGraph"))
        #expect(AtollSettingsBridge.value(for: "stats.showCpuGraph") == .bool(false))

        #expect(AtollSettingsBridge.setValue(.double(9), for: "stats.statsUpdateInterval"))
        #expect(AtollSettingsBridge.value(for: "stats.statsUpdateInterval") == .double(9))

        #expect(AtollSettingsBridge.setValue(.int(7), for: "clipboard.clipboardHistorySize"))
        #expect(AtollSettingsBridge.value(for: "clipboard.clipboardHistorySize") == .int(7))

        #expect(AtollSettingsBridge.setValue(.string("/bin/bash"), for: "terminal.terminalShellPath"))
        #expect(AtollSettingsBridge.value(for: "terminal.terminalShellPath") == .string("/bin/bash"))

        let color = AtollSettingColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
        #expect(AtollSettingsBridge.setValue(.color(color), for: "terminal.terminalBackgroundColor"))
        #expect(AtollSettingsBridge.value(for: "terminal.terminalBackgroundColor") == .color(color))
    }

    @Test("Unknown setting identifiers fail safely")
    func unknownIdentifiersFailSafely() {
        #expect(AtollSettingsBridge.value(for: "missing.setting") == nil)
        #expect(!AtollSettingsBridge.setValue(.bool(true), for: "missing.setting"))
    }

    @Test("Sync preserves user-tuned deep settings")
    func syncPreservesDeepSettings() {
        let originalFeatures = AtollDefaultsBridge.featuresFromCurrentDefaults
        let originalStatsGraph = AtollSettingsBridge.value(for: "stats.showCpuGraph")
        let originalMediaAutoHide = AtollSettingsBridge.value(for: "media.autoHideInactiveNotchMediaPlayer")
        let originalTerminalFont = AtollSettingsBridge.value(for: "terminal.terminalFontSize")
        defer {
            if let originalStatsGraph {
                _ = AtollSettingsBridge.setValue(originalStatsGraph, for: "stats.showCpuGraph")
            }
            if let originalMediaAutoHide {
                _ = AtollSettingsBridge.setValue(originalMediaAutoHide, for: "media.autoHideInactiveNotchMediaPlayer")
            }
            if let originalTerminalFont {
                _ = AtollSettingsBridge.setValue(originalTerminalFont, for: "terminal.terminalFontSize")
            }
            AtollDefaultsBridge.sync(
                AtollIslandConfiguration(
                    enabledFeatures: originalFeatures,
                    openNotchWidth: 640,
                    openOnHover: true,
                    showOnAllDisplays: false,
                    statsUpdateInterval: 3
                )
            )
        }

        #expect(AtollSettingsBridge.setValue(.bool(false), for: "stats.showCpuGraph"))
        #expect(AtollSettingsBridge.setValue(.bool(false), for: "media.autoHideInactiveNotchMediaPlayer"))
        #expect(AtollSettingsBridge.setValue(.double(18), for: "terminal.terminalFontSize"))

        AtollDefaultsBridge.sync(
            AtollIslandConfiguration(
                enabledFeatures: [.media, .stats, .terminal],
                openNotchWidth: 640,
                openOnHover: true,
                showOnAllDisplays: false,
                statsUpdateInterval: 1
            )
        )

        #expect(AtollSettingsBridge.value(for: "stats.showCpuGraph") == .bool(false))
        #expect(AtollSettingsBridge.value(for: "media.autoHideInactiveNotchMediaPlayer") == .bool(false))
        #expect(AtollSettingsBridge.value(for: "terminal.terminalFontSize") == .double(18))
    }

    @Test("Sync updates module availability gates")
    func syncUpdatesAvailabilityGates() {
        let originalFeatures = AtollDefaultsBridge.featuresFromCurrentDefaults
        defer {
            AtollDefaultsBridge.sync(
                AtollIslandConfiguration(
                    enabledFeatures: originalFeatures,
                    openNotchWidth: 640,
                    openOnHover: true,
                    showOnAllDisplays: false,
                    statsUpdateInterval: 3
                )
            )
        }

        AtollDefaultsBridge.sync(
            AtollIslandConfiguration(
                enabledFeatures: [],
                openNotchWidth: 640,
                openOnHover: true,
                showOnAllDisplays: false,
                statsUpdateInterval: 3
            )
        )
        #expect(!AtollDefaultsBridge.featuresFromCurrentDefaults.contains(.stats))

        AtollDefaultsBridge.sync(
            AtollIslandConfiguration(
                enabledFeatures: [.stats],
                openNotchWidth: 640,
                openOnHover: true,
                showOnAllDisplays: false,
                statsUpdateInterval: 3
            )
        )
        #expect(AtollDefaultsBridge.featuresFromCurrentDefaults.contains(.stats))
    }
}
