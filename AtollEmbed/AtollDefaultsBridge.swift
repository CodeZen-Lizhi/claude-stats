import CoreGraphics
import Defaults
import Foundation

public enum AtollDefaultsBridge {
    @MainActor
    public static func sync(_ configuration: AtollIslandConfiguration) {
        let features = configuration.enabledFeatures

        Defaults[.openNotchOnHover] = configuration.openOnHover
        Defaults[.showOnAllDisplays] = configuration.showOnAllDisplays

        Defaults[.showStandardMediaControls] = features.contains(.media)
        Defaults[.showCalendar] = features.contains(.calendar)
        Defaults[.dynamicShelf] = features.contains(.shelf)

        Defaults[.enableTimerFeature] = features.contains(.timer)

        Defaults[.enableStatsFeature] = features.contains(.stats)

        Defaults[.enableClipboardManager] = features.contains(.clipboard)

        Defaults[.enableColorPickerFeature] = features.contains(.colorPicker)

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
        syncOSDAvailability(features.contains(.osd))

        Defaults[.enableLockScreenLiveActivity] = features.contains(.lockScreenWidgets)

        Defaults[.enableThirdPartyExtensions] = features.contains(.extensionBridge)

        Defaults[.enableScreenAssistant] = features.contains(.screenAssistant)
        Defaults[.enableTerminalFeature] = features.contains(.terminal)

        Defaults[.openNotchWidth] = resolvedOpenWidth(
            requested: configuration.openNotchWidth,
            features: features,
            maxAllowedWidth: maxAllowedNotchWidth()
        )
    }

    private static func syncOSDAvailability(_ isEnabled: Bool) {
        guard isEnabled else {
            Defaults[.enableSystemHUD] = false
            Defaults[.enableCustomOSD] = false
            Defaults[.enableVerticalHUD] = false
            Defaults[.enableCircularHUD] = false
            return
        }

        if !Defaults[.enableCustomOSD],
           !Defaults[.enableVerticalHUD],
           !Defaults[.enableCircularHUD] {
            Defaults[.enableSystemHUD] = true
        }
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
        if Defaults[.enableTerminalFeature] {
            features.insert(.terminal)
        }
        return features
    }
}
