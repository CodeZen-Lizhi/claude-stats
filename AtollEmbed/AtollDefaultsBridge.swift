import CoreGraphics
import Defaults
import Foundation

public enum AtollDefaultsBridge {
    @MainActor
    public static func sync(_ configuration: AtollIslandConfiguration) {
        let features = configuration.enabledFeatures

        Defaults[.openNotchOnHover] = configuration.openOnHover
        Defaults[.showOnAllDisplays] = configuration.showOnAllDisplays
        Defaults[.statsUpdateInterval] = configuration.statsUpdateInterval
        Defaults[.externalDisplayStylesByScreenID] = configuration.screenStylesByScreenID.mapValues {
            $0.externalDisplayStyle.rawValue
        }

        let mediaEnabled = features.contains(.media)
        let calendarEnabled = features.contains(.calendar)
        let shelfEnabled = features.contains(.shelf)
        let batteryEnabled = features.contains(.battery)
        let privacyEnabled = features.contains(.privacy)
        let recordingEnabled = features.contains(.recording)
        let focusEnabled = features.contains(.focus)
        let bluetoothEnabled = features.contains(.bluetooth)
        let downloadsEnabled = features.contains(.downloads)
        let osdEnabled = features.contains(.osd)
        let lockScreenEnabled = features.contains(.lockScreenWidgets)
        let extensionsEnabled = features.contains(.extensionBridge)

        Defaults[.showStandardMediaControls] = mediaEnabled
        syncCalendarAvailability(calendarEnabled)
        Defaults[.dynamicShelf] = shelfEnabled

        Defaults[.enableTimerFeature] = features.contains(.timer)
        Defaults[.enableStatsFeature] = features.contains(.stats)
        Defaults[.enableClipboardManager] = features.contains(.clipboard)
        Defaults[.enableColorPickerFeature] = features.contains(.colorPicker)

        syncBatteryAvailability(batteryEnabled)
        syncPrivacyAvailability(privacyEnabled)
        syncRecordingAvailability(recordingEnabled)
        syncFocusAvailability(focusEnabled)

        Defaults[.showBluetoothDeviceConnections] = bluetoothEnabled
        Defaults[.enableDownloadListener] = downloadsEnabled
        syncOSDAvailability(osdEnabled)
        syncLockScreenAvailability(lockScreenEnabled)
        syncExtensionAvailability(extensionsEnabled, lockScreenEnabled: lockScreenEnabled)

        Defaults[.enableScreenAssistant] = features.contains(.screenAssistant)
        Defaults[.enableTerminalFeature] = false

        Defaults[.openNotchWidth] = resolvedOpenWidth(
            requested: configuration.openNotchWidth,
            features: features,
            maxAllowedWidth: maxAllowedNotchWidth()
        )
    }

    private static func syncCalendarAvailability(_ isEnabled: Bool) {
        Defaults[.showCalendar] = isEnabled
        Defaults[.enableReminderLiveActivity] = isEnabled
    }

    private static func syncBatteryAvailability(_ isEnabled: Bool) {
        Defaults[.showBatteryIndicator] = isEnabled
        Defaults[.showPowerStatusNotifications] = isEnabled
        Defaults[.showChargingBatteryHUD] = isEnabled
        Defaults[.showLowBatteryHUD] = isEnabled
        Defaults[.showFullBatteryHUD] = isEnabled
    }

    private static func syncPrivacyAvailability(_ isEnabled: Bool) {
        Defaults[.enableCameraDetection] = isEnabled
        Defaults[.enableMicrophoneDetection] = isEnabled
    }

    private static func syncRecordingAvailability(_ isEnabled: Bool) {
        Defaults[.enableScreenRecordingDetection] = isEnabled
        Defaults[.showRecordingIndicator] = isEnabled
    }

    private static func syncFocusAvailability(_ isEnabled: Bool) {
        Defaults[.enableDoNotDisturbDetection] = isEnabled
        Defaults[.showDoNotDisturbIndicator] = isEnabled
    }

    private static func syncOSDAvailability(_ isEnabled: Bool) {
        guard isEnabled else {
            Defaults[.enableSystemHUD] = false
            Defaults[.enableVolumeHUD] = false
            Defaults[.enableBrightnessHUD] = false
            Defaults[.enableKeyboardBacklightHUD] = false
            Defaults[.enableCustomOSD] = false
            Defaults[.enableOSDVolume] = false
            Defaults[.enableOSDBrightness] = false
            Defaults[.enableOSDKeyboardBacklight] = false
            Defaults[.enableVerticalHUD] = false
            Defaults[.enableCircularHUD] = false
            Defaults[.enableCapsLockIndicator] = false
            return
        }

        Defaults[.enableVolumeHUD] = true
        Defaults[.enableBrightnessHUD] = true
        Defaults[.enableKeyboardBacklightHUD] = true
        Defaults[.enableOSDVolume] = true
        Defaults[.enableOSDBrightness] = true
        Defaults[.enableOSDKeyboardBacklight] = true
        Defaults[.enableCapsLockIndicator] = true
        Defaults[.enableSystemHUD] = true
        Defaults[.enableCustomOSD] = false
        Defaults[.enableVerticalHUD] = false
        Defaults[.enableCircularHUD] = false
    }

    private static func syncLockScreenAvailability(_ isEnabled: Bool) {
        Defaults[.enableLockScreenLiveActivity] = isEnabled
        Defaults[.enableLockScreenMediaWidget] = isEnabled
        Defaults[.enableLockScreenWeatherWidget] = isEnabled
        Defaults[.enableLockScreenFocusWidget] = isEnabled
        Defaults[.enableLockScreenReminderWidget] = isEnabled
        Defaults[.enableLockScreenTimerWidget] = isEnabled
    }

    private static func syncExtensionAvailability(_ isEnabled: Bool, lockScreenEnabled: Bool) {
        Defaults[.enableThirdPartyExtensions] = isEnabled
        Defaults[.enableExtensionLiveActivities] = isEnabled
        Defaults[.enableExtensionLockScreenWidgets] = isEnabled && lockScreenEnabled
        Defaults[.enableExtensionNotchExperiences] = isEnabled
        Defaults[.enableExtensionNotchTabs] = isEnabled
        Defaults[.enableExtensionNotchMinimalisticOverrides] = isEnabled
        Defaults[.enableExtensionNotchInteractiveWebViews] = isEnabled
        Defaults[.enableExtensionFileSharing] = isEnabled
    }

    public static func standardTabCount(for features: Set<AtollIslandFeature>) -> Int {
        var count = 0
        if features.contains(.media) || features.contains(.calendar) {
            count += 1
        }
        if features.contains(.shelf) {
            count += 1
        }
        if features.contains(.timer) {
            count += 1
        }
        if features.contains(.stats) {
            count += 1
        }
        if features.contains(.clipboard) {
            count += 1
        }
        return count
    }

    public static func recommendedMinimumWidth(for features: Set<AtollIslandFeature>) -> CGFloat {
        recommendedMinimumWidth(forStandardTabCount: standardTabCount(for: features))
    }

    public static func recommendedMinimumWidth(forStandardTabCount count: Int) -> CGFloat {
        if count >= 6 { return 770 }
        if count >= 5 { return 690 }
        return 640
    }

    public static func resolvedOpenWidth(
        requested: CGFloat,
        features: Set<AtollIslandFeature>,
        maxAllowedWidth: CGFloat
    ) -> CGFloat {
        min(max(requested, recommendedMinimumWidth(for: features)), maxAllowedWidth)
    }

    @MainActor
    public static var featuresFromCurrentDefaults: Set<AtollIslandFeature> {
        var features: Set<AtollIslandFeature> = []
        if Defaults[.showStandardMediaControls] {
            features.insert(.media)
        }
        if Defaults[.showCalendar] {
            features.insert(.calendar)
        }
        if Defaults[.dynamicShelf] {
            features.insert(.shelf)
        }
        if Defaults[.enableTimerFeature], Defaults[.timerDisplayMode] == .tab {
            features.insert(.timer)
        }
        if Defaults[.enableStatsFeature] {
            features.insert(.stats)
        }
        if Defaults[.enableClipboardManager], Defaults[.clipboardDisplayMode] == .separateTab {
            features.insert(.clipboard)
        }
        return features
    }
}
