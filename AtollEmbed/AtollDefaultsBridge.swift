import CoreGraphics
import Defaults
import Foundation

public enum AtollDefaultsBridge {
    @MainActor
    public static func sync(_ configuration: AtollIslandConfiguration) {
        let features = configuration.enabledFeatures

        Defaults[.openNotchOnHover] = configuration.openOnHover
        Defaults[.minimumHoverDuration] = 0.3
        Defaults[.showOnAllDisplays] = configuration.showOnAllDisplays
        Defaults[.settingsIconInNotch] = true
        Defaults[.enableMinimalisticUI] = false
        Defaults[.hideNonNotchUntilHover] = false
        Defaults[.externalDisplayStyle] = .dynamicIsland

        Defaults[.showStandardMediaControls] = features.contains(.media)
        Defaults[.showCalendar] = features.contains(.calendar)
        Defaults[.showMirror] = false
        Defaults[.dynamicShelf] = features.contains(.shelf)

        Defaults[.enableTimerFeature] = features.contains(.timer)
        Defaults[.timerDisplayMode] = .tab
        Defaults[.timerControlWindowEnabled] = false

        Defaults[.enableStatsFeature] = features.contains(.stats)
        Defaults[.statsUpdateInterval] = configuration.statsUpdateInterval
        Defaults[.showCpuGraph] = features.contains(.stats)
        Defaults[.showMemoryGraph] = features.contains(.stats)
        Defaults[.showGpuGraph] = features.contains(.stats)

        Defaults[.enableClipboardManager] = features.contains(.clipboard)
        Defaults[.clipboardDisplayMode] = .separateTab
        Defaults[.showClipboardIcon] = false
        Defaults[.enableNotes] = false

        Defaults[.enableColorPickerFeature] = features.contains(.colorPicker)
        Defaults[.showColorPickerIcon] = features.contains(.colorPicker)
        Defaults[.colorPickerDisplayMode] = .popover

        Defaults[.showBatteryIndicator] = features.contains(.battery)
        Defaults[.showPowerStatusNotifications] = features.contains(.battery)

        Defaults[.enableCameraDetection] = features.contains(.privacy)
        Defaults[.enableMicrophoneDetection] = features.contains(.privacy)
        Defaults[.enableScreenRecordingDetection] = features.contains(.recording)
        Defaults[.showRecordingIndicator] = features.contains(.recording)
        Defaults[.enableDoNotDisturbDetection] = features.contains(.focus)
        Defaults[.showDoNotDisturbIndicator] = features.contains(.focus)

        Defaults[.showBluetoothDeviceConnections] = features.contains(.bluetooth)
        Defaults[.enableDownloadListener] = features.contains(.downloads)
        Defaults[.enableSystemHUD] = features.contains(.osd)
        Defaults[.enableCustomOSD] = features.contains(.osd)

        let lockScreenEnabled = features.contains(.lockScreenWidgets)
        Defaults[.enableLockScreenLiveActivity] = lockScreenEnabled
        Defaults[.enableLockScreenMediaWidget] = lockScreenEnabled
        Defaults[.enableLockScreenWeatherWidget] = lockScreenEnabled
        Defaults[.enableLockScreenFocusWidget] = lockScreenEnabled
        Defaults[.enableLockScreenReminderWidget] = lockScreenEnabled
        Defaults[.enableLockScreenTimerWidget] = lockScreenEnabled

        let extensionsEnabled = features.contains(.extensionBridge)
        Defaults[.enableThirdPartyExtensions] = extensionsEnabled
        Defaults[.enableExtensionLiveActivities] = extensionsEnabled
        Defaults[.enableExtensionLockScreenWidgets] = extensionsEnabled
        Defaults[.enableExtensionNotchExperiences] = extensionsEnabled
        Defaults[.enableExtensionNotchTabs] = extensionsEnabled
        Defaults[.enableExtensionFileSharing] = extensionsEnabled

        Defaults[.enableScreenAssistant] = features.contains(.screenAssistant)
        Defaults[.enableTerminalFeature] = features.contains(.terminal)

        Defaults[.openNotchWidth] = resolvedOpenWidth(
            requested: configuration.openNotchWidth,
            features: features,
            maxAllowedWidth: maxAllowedNotchWidth()
        )
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
        if features.contains(.terminal) {
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
    static var featuresFromCurrentDefaults: Set<AtollIslandFeature> {
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
        if Defaults[.enableTerminalFeature] {
            features.insert(.terminal)
        }
        return features
    }
}
