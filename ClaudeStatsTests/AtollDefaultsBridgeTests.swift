@testable import AtollEmbed
import Defaults
import Testing

@Suite("AtollDefaultsBridge")
struct AtollDefaultsBridgeTests {
    @Test("Recommended width follows Atoll tab count thresholds")
    func recommendedWidthFollowsTabThresholds() {
        #expect(AtollDefaultsBridge.standardTabCount(for: [.media]) == 1)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: [.media]) == 640)

        let fiveTabs: Set<AtollIslandFeature> = [.media, .shelf, .timer, .stats, .clipboard]
        #expect(AtollDefaultsBridge.standardTabCount(for: fiveTabs) == 5)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: fiveTabs) == 690)

        let sixTabs = fiveTabs.union([.terminal])
        #expect(AtollDefaultsBridge.standardTabCount(for: sixTabs) == 6)
        #expect(AtollDefaultsBridge.recommendedMinimumWidth(for: sixTabs) == 770)
    }

    @Test("Resolved width never undercuts Atoll recommendation")
    func resolvedWidthDoesNotUndercutRecommendation() {
        let sixTabs: Set<AtollIslandFeature> = [.media, .shelf, .timer, .stats, .clipboard, .terminal]

        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 420,
                features: sixTabs,
                maxAllowedWidth: 900
            ) == 770
        )
        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 840,
                features: sixTabs,
                maxAllowedWidth: 900
            ) == 840
        )
        #expect(
            AtollDefaultsBridge.resolvedOpenWidth(
                requested: 840,
                features: sixTabs,
                maxAllowedWidth: 700
            ) == 700
        )
    }

    @Test("Sync maps module gates to Atoll automatic trigger defaults")
    @MainActor
    func syncMapsModuleGates() {
        let original = (
            statsUpdateInterval: Defaults[.statsUpdateInterval],
            externalDisplayStylesByScreenID: Defaults[.externalDisplayStylesByScreenID],
            showStandardMediaControls: Defaults[.showStandardMediaControls],
            showCalendar: Defaults[.showCalendar],
            enableReminderLiveActivity: Defaults[.enableReminderLiveActivity],
            dynamicShelf: Defaults[.dynamicShelf],
            enableTimerFeature: Defaults[.enableTimerFeature],
            enableStatsFeature: Defaults[.enableStatsFeature],
            enableClipboardManager: Defaults[.enableClipboardManager],
            enableColorPickerFeature: Defaults[.enableColorPickerFeature],
            showBatteryIndicator: Defaults[.showBatteryIndicator],
            showPowerStatusNotifications: Defaults[.showPowerStatusNotifications],
            showChargingBatteryHUD: Defaults[.showChargingBatteryHUD],
            showLowBatteryHUD: Defaults[.showLowBatteryHUD],
            showFullBatteryHUD: Defaults[.showFullBatteryHUD],
            enableCameraDetection: Defaults[.enableCameraDetection],
            enableMicrophoneDetection: Defaults[.enableMicrophoneDetection],
            enableScreenRecordingDetection: Defaults[.enableScreenRecordingDetection],
            showRecordingIndicator: Defaults[.showRecordingIndicator],
            enableDoNotDisturbDetection: Defaults[.enableDoNotDisturbDetection],
            showDoNotDisturbIndicator: Defaults[.showDoNotDisturbIndicator],
            showBluetoothDeviceConnections: Defaults[.showBluetoothDeviceConnections],
            enableDownloadListener: Defaults[.enableDownloadListener],
            enableSystemHUD: Defaults[.enableSystemHUD],
            enableVolumeHUD: Defaults[.enableVolumeHUD],
            enableBrightnessHUD: Defaults[.enableBrightnessHUD],
            enableKeyboardBacklightHUD: Defaults[.enableKeyboardBacklightHUD],
            enableCustomOSD: Defaults[.enableCustomOSD],
            enableOSDVolume: Defaults[.enableOSDVolume],
            enableOSDBrightness: Defaults[.enableOSDBrightness],
            enableOSDKeyboardBacklight: Defaults[.enableOSDKeyboardBacklight],
            enableVerticalHUD: Defaults[.enableVerticalHUD],
            enableCircularHUD: Defaults[.enableCircularHUD],
            enableCapsLockIndicator: Defaults[.enableCapsLockIndicator],
            enableLockScreenLiveActivity: Defaults[.enableLockScreenLiveActivity],
            enableLockScreenMediaWidget: Defaults[.enableLockScreenMediaWidget],
            enableLockScreenWeatherWidget: Defaults[.enableLockScreenWeatherWidget],
            enableLockScreenFocusWidget: Defaults[.enableLockScreenFocusWidget],
            enableLockScreenReminderWidget: Defaults[.enableLockScreenReminderWidget],
            enableLockScreenTimerWidget: Defaults[.enableLockScreenTimerWidget],
            enableThirdPartyExtensions: Defaults[.enableThirdPartyExtensions],
            enableExtensionLiveActivities: Defaults[.enableExtensionLiveActivities],
            enableExtensionLockScreenWidgets: Defaults[.enableExtensionLockScreenWidgets],
            enableExtensionNotchExperiences: Defaults[.enableExtensionNotchExperiences],
            enableExtensionNotchTabs: Defaults[.enableExtensionNotchTabs],
            enableExtensionNotchMinimalisticOverrides: Defaults[.enableExtensionNotchMinimalisticOverrides],
            enableExtensionNotchInteractiveWebViews: Defaults[.enableExtensionNotchInteractiveWebViews],
            enableExtensionFileSharing: Defaults[.enableExtensionFileSharing],
            enableScreenAssistant: Defaults[.enableScreenAssistant],
            enableTerminalFeature: Defaults[.enableTerminalFeature]
        )
        defer {
            Defaults[.statsUpdateInterval] = original.statsUpdateInterval
            Defaults[.externalDisplayStylesByScreenID] = original.externalDisplayStylesByScreenID
            Defaults[.showStandardMediaControls] = original.showStandardMediaControls
            Defaults[.showCalendar] = original.showCalendar
            Defaults[.enableReminderLiveActivity] = original.enableReminderLiveActivity
            Defaults[.dynamicShelf] = original.dynamicShelf
            Defaults[.enableTimerFeature] = original.enableTimerFeature
            Defaults[.enableStatsFeature] = original.enableStatsFeature
            Defaults[.enableClipboardManager] = original.enableClipboardManager
            Defaults[.enableColorPickerFeature] = original.enableColorPickerFeature
            Defaults[.showBatteryIndicator] = original.showBatteryIndicator
            Defaults[.showPowerStatusNotifications] = original.showPowerStatusNotifications
            Defaults[.showChargingBatteryHUD] = original.showChargingBatteryHUD
            Defaults[.showLowBatteryHUD] = original.showLowBatteryHUD
            Defaults[.showFullBatteryHUD] = original.showFullBatteryHUD
            Defaults[.enableCameraDetection] = original.enableCameraDetection
            Defaults[.enableMicrophoneDetection] = original.enableMicrophoneDetection
            Defaults[.enableScreenRecordingDetection] = original.enableScreenRecordingDetection
            Defaults[.showRecordingIndicator] = original.showRecordingIndicator
            Defaults[.enableDoNotDisturbDetection] = original.enableDoNotDisturbDetection
            Defaults[.showDoNotDisturbIndicator] = original.showDoNotDisturbIndicator
            Defaults[.showBluetoothDeviceConnections] = original.showBluetoothDeviceConnections
            Defaults[.enableDownloadListener] = original.enableDownloadListener
            Defaults[.enableSystemHUD] = original.enableSystemHUD
            Defaults[.enableVolumeHUD] = original.enableVolumeHUD
            Defaults[.enableBrightnessHUD] = original.enableBrightnessHUD
            Defaults[.enableKeyboardBacklightHUD] = original.enableKeyboardBacklightHUD
            Defaults[.enableCustomOSD] = original.enableCustomOSD
            Defaults[.enableOSDVolume] = original.enableOSDVolume
            Defaults[.enableOSDBrightness] = original.enableOSDBrightness
            Defaults[.enableOSDKeyboardBacklight] = original.enableOSDKeyboardBacklight
            Defaults[.enableVerticalHUD] = original.enableVerticalHUD
            Defaults[.enableCircularHUD] = original.enableCircularHUD
            Defaults[.enableCapsLockIndicator] = original.enableCapsLockIndicator
            Defaults[.enableLockScreenLiveActivity] = original.enableLockScreenLiveActivity
            Defaults[.enableLockScreenMediaWidget] = original.enableLockScreenMediaWidget
            Defaults[.enableLockScreenWeatherWidget] = original.enableLockScreenWeatherWidget
            Defaults[.enableLockScreenFocusWidget] = original.enableLockScreenFocusWidget
            Defaults[.enableLockScreenReminderWidget] = original.enableLockScreenReminderWidget
            Defaults[.enableLockScreenTimerWidget] = original.enableLockScreenTimerWidget
            Defaults[.enableThirdPartyExtensions] = original.enableThirdPartyExtensions
            Defaults[.enableExtensionLiveActivities] = original.enableExtensionLiveActivities
            Defaults[.enableExtensionLockScreenWidgets] = original.enableExtensionLockScreenWidgets
            Defaults[.enableExtensionNotchExperiences] = original.enableExtensionNotchExperiences
            Defaults[.enableExtensionNotchTabs] = original.enableExtensionNotchTabs
            Defaults[.enableExtensionNotchMinimalisticOverrides] = original.enableExtensionNotchMinimalisticOverrides
            Defaults[.enableExtensionNotchInteractiveWebViews] = original.enableExtensionNotchInteractiveWebViews
            Defaults[.enableExtensionFileSharing] = original.enableExtensionFileSharing
            Defaults[.enableScreenAssistant] = original.enableScreenAssistant
            Defaults[.enableTerminalFeature] = original.enableTerminalFeature
        }

        AtollDefaultsBridge.sync(
            AtollIslandConfiguration(
                enabledFeatures: [
                    .media,
                    .stats,
                    .clipboard,
                    .colorPicker,
                    .calendar,
                    .shelf,
                    .privacy,
                    .focus,
                    .battery,
                    .bluetooth,
                    .downloads,
                    .osd
                ],
                openNotchWidth: 640,
                openOnHover: true,
                showOnAllDisplays: false,
                statsUpdateInterval: 3,
                screenStylesByScreenID: [
                    "screen-a": .floatingIsland,
                    "screen-b": .sameAsNotch
                ]
            )
        )

        #expect(Defaults[.statsUpdateInterval] == 3)
        #expect(Defaults[.externalDisplayStylesByScreenID] == [
            "screen-a": ExternalDisplayStyle.dynamicIsland.rawValue,
            "screen-b": ExternalDisplayStyle.notch.rawValue
        ])
        #expect(Defaults[.showStandardMediaControls])
        #expect(Defaults[.showCalendar])
        #expect(Defaults[.enableReminderLiveActivity])
        #expect(Defaults[.dynamicShelf])
        #expect(Defaults[.enableStatsFeature])
        #expect(Defaults[.enableClipboardManager])
        #expect(Defaults[.enableColorPickerFeature])
        #expect(Defaults[.showBatteryIndicator])
        #expect(Defaults[.showPowerStatusNotifications])
        #expect(Defaults[.showChargingBatteryHUD])
        #expect(Defaults[.showLowBatteryHUD])
        #expect(Defaults[.showFullBatteryHUD])
        #expect(Defaults[.enableCameraDetection])
        #expect(Defaults[.enableMicrophoneDetection])
        #expect(Defaults[.enableDoNotDisturbDetection])
        #expect(Defaults[.showDoNotDisturbIndicator])
        #expect(Defaults[.showBluetoothDeviceConnections])
        #expect(Defaults[.enableDownloadListener])
        #expect(Defaults[.enableSystemHUD])
        #expect(Defaults[.enableVolumeHUD])
        #expect(Defaults[.enableBrightnessHUD])
        #expect(Defaults[.enableKeyboardBacklightHUD])
        #expect(Defaults[.enableOSDVolume])
        #expect(Defaults[.enableOSDBrightness])
        #expect(Defaults[.enableOSDKeyboardBacklight])
        #expect(Defaults[.enableCapsLockIndicator])

        #expect(!Defaults[.enableTimerFeature])
        #expect(!Defaults[.enableScreenRecordingDetection])
        #expect(!Defaults[.showRecordingIndicator])
        #expect(!Defaults[.enableLockScreenLiveActivity])
        #expect(!Defaults[.enableLockScreenMediaWidget])
        #expect(!Defaults[.enableLockScreenWeatherWidget])
        #expect(!Defaults[.enableLockScreenFocusWidget])
        #expect(!Defaults[.enableLockScreenReminderWidget])
        #expect(!Defaults[.enableLockScreenTimerWidget])
        #expect(!Defaults[.enableThirdPartyExtensions])
        #expect(!Defaults[.enableExtensionLiveActivities])
        #expect(!Defaults[.enableExtensionLockScreenWidgets])
        #expect(!Defaults[.enableExtensionNotchExperiences])
        #expect(!Defaults[.enableExtensionNotchTabs])
        #expect(!Defaults[.enableExtensionNotchMinimalisticOverrides])
        #expect(!Defaults[.enableExtensionNotchInteractiveWebViews])
        #expect(!Defaults[.enableExtensionFileSharing])
        #expect(!Defaults[.enableScreenAssistant])
        #expect(!Defaults[.enableTerminalFeature])
    }
}
