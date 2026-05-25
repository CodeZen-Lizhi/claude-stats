import AppKit
import Defaults
import Foundation
import SwiftUI

public enum AtollSettingsTabID: String, CaseIterable, Identifiable, Sendable {
    case island
    case appearance
    case media
    case stats
    case timer
    case clipboard
    case colorPicker
    case calendar
    case shelf
    case privacy
    case recording
    case focus
    case battery
    case bluetooth
    case downloads
    case osd
    case lockScreenWidgets
    case extensionBridge
    case screenAssistant

    public var id: String { rawValue }
}

public struct AtollSettingColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

public enum AtollSettingValue: Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case int(Int)
    case string(String)
    case color(AtollSettingColor)
}

public struct AtollSettingOption: Identifiable, Equatable, Sendable {
    public var id: String { value }
    public var value: String
    public var title: String

    public init(value: String, title: String) {
        self.value = value
        self.title = title
    }
}

public enum AtollSettingControl: Equatable, Sendable {
    case toggle
    case slider(min: Double, max: Double, step: Double, unit: String?)
    case picker([AtollSettingOption])
    case text
    case color
}

public struct AtollSettingDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var description: String?
    public var control: AtollSettingControl

    public init(id: String, title: String, description: String? = nil, control: AtollSettingControl) {
        self.id = id
        self.title = title
        self.description = description
        self.control = control
    }
}

public struct AtollSettingGroupDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var caption: String?
    public var settings: [AtollSettingDescriptor]

    public init(id: String, title: String, caption: String? = nil, settings: [AtollSettingDescriptor]) {
        self.id = id
        self.title = title
        self.caption = caption
        self.settings = settings
    }
}

@MainActor
public enum AtollSettingsBridge {
    public static func groups(for tab: AtollSettingsTabID) -> [AtollSettingGroupDescriptor] {
        catalog[tab] ?? []
    }

    public static func value(for settingID: String) -> AtollSettingValue? {
        switch settingID {
        case "island.minimumHoverDuration": .double(Defaults[.minimumHoverDuration])
        case "island.extendHoverArea": .bool(Defaults[.extendHoverArea])
        case "island.enableHaptics": .bool(Defaults[.enableHaptics])
        case "island.hideFromScreenCapture": .bool(Defaults[.hideDynamicIslandFromScreenCapture])
        case "island.hideNonNotchUntilHover": .bool(Defaults[.hideNonNotchUntilHover])
        case "island.externalDisplayStyle": .string(Defaults[.externalDisplayStyle].rawValue)

        case "appearance.settingsIconInNotch": .bool(Defaults[.settingsIconInNotch])
        case "appearance.enableShadow": .bool(Defaults[.enableShadow])
        case "appearance.cornerRadiusScaling": .bool(Defaults[.cornerRadiusScaling])
        case "appearance.useModernCloseAnimation": .bool(Defaults[.useModernCloseAnimation])
        case "appearance.coloredSpectrogram": .bool(Defaults[.coloredSpectrogram])
        case "appearance.playerColorTinting": .bool(Defaults[.playerColorTinting])
        case "appearance.lightingEffect": .bool(Defaults[.lightingEffect])
        case "appearance.sliderColor": .string(Defaults[.sliderColor].rawValue)
        case "appearance.showMirror": .bool(Defaults[.showMirror])
        case "appearance.mirrorShape": .string(Defaults[.mirrorShape].rawValue)
        case "appearance.showNotHumanFace": .bool(Defaults[.showNotHumanFace])

        case "media.mediaController": .string(Defaults[.mediaController].rawValue)
        case "media.autoHideInactiveNotchMediaPlayer": .bool(Defaults[.autoHideInactiveNotchMediaPlayer])
        case "media.showShuffleAndRepeat": .bool(Defaults[.showShuffleAndRepeat])
        case "media.showMediaOutputControl": .bool(Defaults[.showMediaOutputControl])
        case "media.musicControlWindowEnabled": .bool(Defaults[.musicControlWindowEnabled])
        case "media.musicSkipBehavior": .string(Defaults[.musicSkipBehavior].rawValue)
        case "media.enableSneakPeek": .bool(Defaults[.enableSneakPeek])
        case "media.showSneakPeekOnTrackChange": .bool(Defaults[.showSneakPeekOnTrackChange])
        case "media.sneakPeekStyles": .string(Defaults[.sneakPeekStyles].rawValue)
        case "media.waitInterval": .double(Defaults[.waitInterval])
        case "media.enableLyrics": .bool(Defaults[.enableLyrics])
        case "media.showLiveCanvasInDynamicIsland": .bool(Defaults[.showLiveCanvasInDynamicIsland])
        case "media.parallaxEffectIntensity": .double(Defaults[.parallaxEffectIntensity])
        case "media.enableRealTimeWaveform": .bool(Defaults[.enableRealTimeWaveform])
        case "media.enableLockScreenMediaWidget": .bool(Defaults[.enableLockScreenMediaWidget])
        case "media.lockScreenShowAppIcon": .bool(Defaults[.lockScreenShowAppIcon])
        case "media.lockScreenPanelShowsBorder": .bool(Defaults[.lockScreenPanelShowsBorder])
        case "media.lockScreenPanelUsesBlur": .bool(Defaults[.lockScreenPanelUsesBlur])
        case "media.lockScreenMusicAlbumParallaxEnabled": .bool(Defaults[.lockScreenMusicAlbumParallaxEnabled])
        case "media.lockScreenMusicFullscreenArtworkEnabled": .bool(Defaults[.lockScreenMusicFullscreenArtworkEnabled])

        case "stats.statsStopWhenNotchCloses": .bool(Defaults[.statsStopWhenNotchCloses])
        case "stats.statsUpdateInterval": .double(Defaults[.statsUpdateInterval])
        case "stats.showCpuGraph": .bool(Defaults[.showCpuGraph])
        case "stats.showMemoryGraph": .bool(Defaults[.showMemoryGraph])
        case "stats.showGpuGraph": .bool(Defaults[.showGpuGraph])
        case "stats.showNetworkGraph": .bool(Defaults[.showNetworkGraph])
        case "stats.showDiskGraph": .bool(Defaults[.showDiskGraph])
        case "stats.cpuTemperatureUnit": .string(Defaults[.cpuTemperatureUnit].rawValue)

        case "timer.timerDisplayMode": .string(Defaults[.timerDisplayMode].rawValue)
        case "timer.mirrorSystemTimer": .bool(Defaults[.mirrorSystemTimer])
        case "timer.timerControlWindowEnabled": .bool(Defaults[.timerControlWindowEnabled])
        case "timer.showTimerPresetsInNotchTab": .bool(Defaults[.showTimerPresetsInNotchTab])
        case "timer.timerIconColorMode": .string(Defaults[.timerIconColorMode].rawValue)
        case "timer.timerSolidColor": colorValue(Defaults[.timerSolidColor])
        case "timer.timerShowsCountdown": .bool(Defaults[.timerShowsCountdown])
        case "timer.timerShowsLabel": .bool(Defaults[.timerShowsLabel])
        case "timer.timerShowsProgress": .bool(Defaults[.timerShowsProgress])
        case "timer.timerProgressStyle": .string(Defaults[.timerProgressStyle].rawValue)
        case "timer.enableLockScreenTimerWidget": .bool(Defaults[.enableLockScreenTimerWidget])
        case "timer.lockScreenTimerWidgetUsesBlur": .bool(Defaults[.lockScreenTimerWidgetUsesBlur])
        case "timer.lockScreenTimerGlassStyle": .string(Defaults[.lockScreenTimerGlassStyle].rawValue)
        case "timer.lockScreenTimerGlassCustomizationMode": .string(Defaults[.lockScreenTimerGlassCustomizationMode].rawValue)
        case "timer.lockScreenTimerLiquidGlassVariant": .int(Defaults[.lockScreenTimerLiquidGlassVariant].rawValue)

        case "clipboard.showClipboardIcon": .bool(Defaults[.showClipboardIcon])
        case "clipboard.clipboardDisplayMode": .string(Defaults[.clipboardDisplayMode].rawValue)
        case "clipboard.clipboardHistorySize": .int(Defaults[.clipboardHistorySize])

        case "colorPicker.showColorPickerIcon": .bool(Defaults[.showColorPickerIcon])
        case "colorPicker.colorPickerDisplayMode": .string(Defaults[.colorPickerDisplayMode].rawValue)
        case "colorPicker.colorHistorySize": .int(Defaults[.colorHistorySize])
        case "colorPicker.showColorFormats": .bool(Defaults[.showColorFormats])

        case "calendar.hideCompletedReminders": .bool(Defaults[.hideCompletedReminders])
        case "calendar.showFullEventTitles": .bool(Defaults[.showFullEventTitles])
        case "calendar.autoScrollToNextEvent": .bool(Defaults[.autoScrollToNextEvent])
        case "calendar.hideAllDayEvents": .bool(Defaults[.hideAllDayEvents])
        case "calendar.enableReminderLiveActivity": .bool(Defaults[.enableReminderLiveActivity])
        case "calendar.reminderPresentationStyle": .string(Defaults[.reminderPresentationStyle].rawValue)
        case "calendar.reminderLeadTime": .int(Defaults[.reminderLeadTime])
        case "calendar.reminderSneakPeekDuration": .double(Defaults[.reminderSneakPeekDuration])
        case "calendar.enableLockScreenReminderWidget": .bool(Defaults[.enableLockScreenReminderWidget])
        case "calendar.lockScreenReminderChipStyle": .string(Defaults[.lockScreenReminderChipStyle].rawValue)
        case "calendar.lockScreenShowCalendarEvent": .bool(Defaults[.lockScreenShowCalendarEvent])
        case "calendar.lockScreenCalendarEventLookaheadWindow": .string(Defaults[.lockScreenCalendarEventLookaheadWindow])
        case "calendar.lockScreenShowCalendarCountdown": .bool(Defaults[.lockScreenShowCalendarCountdown])
        case "calendar.lockScreenShowCalendarEventEntireDuration": .bool(Defaults[.lockScreenShowCalendarEventEntireDuration])
        case "calendar.lockScreenShowCalendarTimeRemaining": .bool(Defaults[.lockScreenShowCalendarTimeRemaining])
        case "calendar.lockScreenShowCalendarStartTimeAfterBegins": .bool(Defaults[.lockScreenShowCalendarStartTimeAfterBegins])
        case "calendar.enableThirdPartyCalendarApp": .bool(Defaults[.enableThirdPartyCalendarApp])
        case "calendar.selectedCalendarApp": .string(Defaults[.selectedCalendarApp].rawValue)
        case "calendar.fantasticalDefaultView": .string(Defaults[.fantasticalDefaultView].rawValue)

        case "shelf.openShelfByDefault": .bool(Defaults[.openShelfByDefault])
        case "shelf.expandedDragDetection": .bool(Defaults[.expandedDragDetection])
        case "shelf.copyOnDrag": .bool(Defaults[.copyOnDrag])
        case "shelf.autoRemoveShelfItems": .bool(Defaults[.autoRemoveShelfItems])
        case "shelf.quickShareProvider": .string(Defaults[.quickShareProvider])
        case "shelf.localSendDevicePickerGlassMode": .string(Defaults[.localSendDevicePickerGlassMode].rawValue)
        case "shelf.localSendDevicePickerLiquidGlassVariant": .int(Defaults[.localSendDevicePickerLiquidGlassVariant].rawValue)

        case "privacy.showDoNotDisturbLabel": .bool(Defaults[.showDoNotDisturbLabel])
        case "privacy.focusIndicatorNonPersistent": .bool(Defaults[.focusIndicatorNonPersistent])
        case "privacy.enableCapsLockIndicator": .bool(Defaults[.enableCapsLockIndicator])
        case "privacy.capsLockIndicatorTintMode": .string(Defaults[.capsLockIndicatorTintMode].rawValue)
        case "privacy.showCapsLockLabel": .bool(Defaults[.showCapsLockLabel])

        case "recording.hideFromScreenCapture": .bool(Defaults[.hideDynamicIslandFromScreenCapture])
        case "focus.focusIndicatorNonPersistent": .bool(Defaults[.focusIndicatorNonPersistent])
        case "focus.showDoNotDisturbLabel": .bool(Defaults[.showDoNotDisturbLabel])
        case "focus.focusMonitoringMode": .string(Defaults[.focusMonitoringMode].rawValue)

        case "battery.showBatteryPercentage": .bool(Defaults[.showBatteryPercentage])
        case "battery.showPowerStatusIcons": .bool(Defaults[.showPowerStatusIcons])
        case "battery.playLowBatteryAlertSound": .bool(Defaults[.playLowBatteryAlertSound])
        case "battery.showChargingBatteryHUD": .bool(Defaults[.showChargingBatteryHUD])
        case "battery.showLowBatteryHUD": .bool(Defaults[.showLowBatteryHUD])
        case "battery.showFullBatteryHUD": .bool(Defaults[.showFullBatteryHUD])
        case "battery.chargingBatteryHUDDuration": .int(Defaults[.chargingBatteryHUDDuration])
        case "battery.lowBatteryHUDDuration": .int(Defaults[.lowBatteryHUDDuration])
        case "battery.fullBatteryHUDDuration": .int(Defaults[.fullBatteryHUDDuration])
        case "battery.lowBatteryHUDThreshold": .int(Defaults[.lowBatteryHUDThreshold])
        case "battery.fullBatteryHUDThreshold": .int(Defaults[.fullBatteryHUDThreshold])
        case "battery.lowBatteryHUDStyle": .string(Defaults[.lowBatteryHUDStyle].rawValue)
        case "battery.fullBatteryHUDStyle": .string(Defaults[.fullBatteryHUDStyle].rawValue)

        case "bluetooth.useCircularBluetoothBatteryIndicator": .bool(Defaults[.useCircularBluetoothBatteryIndicator])
        case "bluetooth.showBluetoothBatteryPercentageText": .bool(Defaults[.showBluetoothBatteryPercentageText])
        case "bluetooth.showBluetoothDeviceNameMarquee": .bool(Defaults[.showBluetoothDeviceNameMarquee])
        case "bluetooth.useBluetoothHUD3DIcon": .bool(Defaults[.useBluetoothHUD3DIcon])
        case "bluetooth.useColorCodedBatteryDisplay": .bool(Defaults[.useColorCodedBatteryDisplay])

        case "downloads.selectedDownloadIndicatorStyle": .string(Defaults[.selectedDownloadIndicatorStyle].rawValue)
        case "downloads.selectedDownloadIconStyle": .string(Defaults[.selectedDownloadIconStyle].rawValue)

        case "osd.enableVolumeHUD": .bool(Defaults[.enableVolumeHUD])
        case "osd.enableBrightnessHUD": .bool(Defaults[.enableBrightnessHUD])
        case "osd.enableKeyboardBacklightHUD": .bool(Defaults[.enableKeyboardBacklightHUD])
        case "osd.playVolumeChangeFeedback": .bool(Defaults[.playVolumeChangeFeedback])
        case "osd.useColorCodedVolumeDisplay": .bool(Defaults[.useColorCodedVolumeDisplay])
        case "osd.useSmoothColorGradient": .bool(Defaults[.useSmoothColorGradient])
        case "osd.showProgressPercentages": .bool(Defaults[.showProgressPercentages])
        case "osd.inlineHUD": .bool(Defaults[.inlineHUD])
        case "osd.progressBarStyle": .string(Defaults[.progressBarStyle].rawValue)
        case "osd.systemEventIndicatorShadow": .bool(Defaults[.systemEventIndicatorShadow])
        case "osd.systemEventIndicatorUseAccent": .bool(Defaults[.systemEventIndicatorUseAccent])
        case "osd.enableCustomOSD": .bool(Defaults[.enableCustomOSD])
        case "osd.enableVerticalHUD": .bool(Defaults[.enableVerticalHUD])
        case "osd.enableCircularHUD": .bool(Defaults[.enableCircularHUD])
        case "osd.osdMaterial": .string(Defaults[.osdMaterial].rawValue)
        case "osd.osdIconColorStyle": .string(Defaults[.osdIconColorStyle].rawValue)
        case "osd.verticalHUDPosition": .string(Defaults[.verticalHUDPosition])
        case "osd.verticalHUDShowValue": .bool(Defaults[.verticalHUDShowValue])
        case "osd.verticalHUDInteractive": .bool(Defaults[.verticalHUDInteractive])
        case "osd.verticalHUDUseAccentColor": .bool(Defaults[.verticalHUDUseAccentColor])
        case "osd.verticalHUDWidth": .double(Double(Defaults[.verticalHUDWidth]))
        case "osd.verticalHUDHeight": .double(Double(Defaults[.verticalHUDHeight]))
        case "osd.verticalHUDPadding": .double(Double(Defaults[.verticalHUDPadding]))

        case "lockScreen.enableLockSounds": .bool(Defaults[.enableLockSounds])
        case "lockScreen.lockScreenGlassStyle": .string(Defaults[.lockScreenGlassStyle].rawValue)
        case "lockScreen.lockScreenGlassCustomizationMode": .string(Defaults[.lockScreenGlassCustomizationMode].rawValue)
        case "lockScreen.lockScreenMusicLiquidGlassVariant": .int(Defaults[.lockScreenMusicLiquidGlassVariant].rawValue)
        case "lockScreen.enableLockScreenWeatherWidget": .bool(Defaults[.enableLockScreenWeatherWidget])
        case "lockScreen.lockScreenWeatherWidgetStyle": .string(Defaults[.lockScreenWeatherWidgetStyle].rawValue)
        case "lockScreen.lockScreenWeatherProviderSource": .string(Defaults[.lockScreenWeatherProviderSource].rawValue)
        case "lockScreen.lockScreenWeatherTemperatureUnit": .string(Defaults[.lockScreenWeatherTemperatureUnit].rawValue)
        case "lockScreen.lockScreenWeatherShowsLocation": .bool(Defaults[.lockScreenWeatherShowsLocation])
        case "lockScreen.lockScreenWeatherShowsSunrise": .bool(Defaults[.lockScreenWeatherShowsSunrise])
        case "lockScreen.lockScreenWeatherShowsAQI": .bool(Defaults[.lockScreenWeatherShowsAQI])
        case "lockScreen.lockScreenWeatherAQIScale": .string(Defaults[.lockScreenWeatherAQIScale].rawValue)
        case "lockScreen.lockScreenWeatherUsesGaugeTint": .bool(Defaults[.lockScreenWeatherUsesGaugeTint])
        case "lockScreen.lockScreenBatteryShowsBatteryGauge": .bool(Defaults[.lockScreenBatteryShowsBatteryGauge])
        case "lockScreen.lockScreenBatteryUsesLaptopSymbol": .bool(Defaults[.lockScreenBatteryUsesLaptopSymbol])
        case "lockScreen.lockScreenBatteryShowsCharging": .bool(Defaults[.lockScreenBatteryShowsCharging])
        case "lockScreen.lockScreenBatteryShowsChargingPercentage": .bool(Defaults[.lockScreenBatteryShowsChargingPercentage])
        case "lockScreen.lockScreenBatteryShowsBluetooth": .bool(Defaults[.lockScreenBatteryShowsBluetooth])

        case "extensions.enableExtensionDiagnosticsLogging": .bool(Defaults[.extensionDiagnosticsLoggingEnabled])
        case "extensions.enableExtensionNotchMinimalisticOverrides": .bool(Defaults[.enableExtensionNotchMinimalisticOverrides])
        case "extensions.enableExtensionNotchInteractiveWebViews": .bool(Defaults[.enableExtensionNotchInteractiveWebViews])
        case "extensions.enableExtensionFileSharing": .bool(Defaults[.enableExtensionFileSharing])
        case "extensions.extensionLiveActivityCapacity": .int(Defaults[.extensionLiveActivityCapacity])
        case "extensions.extensionLockScreenWidgetCapacity": .int(Defaults[.extensionLockScreenWidgetCapacity])
        case "extensions.extensionNotchExperienceCapacity": .int(Defaults[.extensionNotchExperienceCapacity])

        case "screenAssistant.screenAssistantDisplayMode": .string(Defaults[.screenAssistantDisplayMode].rawValue)
        case "screenAssistant.selectedAIProvider": .string(Defaults[.selectedAIProvider].rawValue)
        case "screenAssistant.enableThinkingMode": .bool(Defaults[.enableThinkingMode])
        case "screenAssistant.localModelEndpoint": .string(Defaults[.localModelEndpoint])

        default:
            nil
        }
    }

    @discardableResult
    public static func setValue(_ value: AtollSettingValue, for settingID: String) -> Bool {
        switch settingID {
        case "island.minimumHoverDuration": return setDouble(value) { Defaults[.minimumHoverDuration] = $0 }
        case "island.extendHoverArea": return setBool(value) { Defaults[.extendHoverArea] = $0 }
        case "island.enableHaptics": return setBool(value) { Defaults[.enableHaptics] = $0 }
        case "island.hideFromScreenCapture": return setBool(value) { Defaults[.hideDynamicIslandFromScreenCapture] = $0 }
        case "island.hideNonNotchUntilHover": return setBool(value) { Defaults[.hideNonNotchUntilHover] = $0 }
        case "island.externalDisplayStyle": return setStringEnum(value, ExternalDisplayStyle.self) { Defaults[.externalDisplayStyle] = $0 }

        case "appearance.settingsIconInNotch": return setBool(value) { Defaults[.settingsIconInNotch] = $0 }
        case "appearance.enableShadow": return setBool(value) { Defaults[.enableShadow] = $0 }
        case "appearance.cornerRadiusScaling": return setBool(value) { Defaults[.cornerRadiusScaling] = $0 }
        case "appearance.useModernCloseAnimation": return setBool(value) { Defaults[.useModernCloseAnimation] = $0 }
        case "appearance.coloredSpectrogram": return setBool(value) { Defaults[.coloredSpectrogram] = $0 }
        case "appearance.playerColorTinting": return setBool(value) { Defaults[.playerColorTinting] = $0 }
        case "appearance.lightingEffect": return setBool(value) { Defaults[.lightingEffect] = $0 }
        case "appearance.sliderColor": return setStringEnum(value, SliderColorEnum.self) { Defaults[.sliderColor] = $0 }
        case "appearance.showMirror": return setBool(value) { Defaults[.showMirror] = $0 }
        case "appearance.mirrorShape": return setStringEnum(value, MirrorShapeEnum.self) { Defaults[.mirrorShape] = $0 }
        case "appearance.showNotHumanFace": return setBool(value) { Defaults[.showNotHumanFace] = $0 }

        case "media.mediaController": return setStringEnum(value, MediaControllerType.self) { Defaults[.mediaController] = $0 }
        case "media.autoHideInactiveNotchMediaPlayer": return setBool(value) { Defaults[.autoHideInactiveNotchMediaPlayer] = $0 }
        case "media.showShuffleAndRepeat": return setBool(value) { Defaults[.showShuffleAndRepeat] = $0 }
        case "media.showMediaOutputControl": return setBool(value) { Defaults[.showMediaOutputControl] = $0 }
        case "media.musicControlWindowEnabled": return setBool(value) { Defaults[.musicControlWindowEnabled] = $0 }
        case "media.musicSkipBehavior": return setStringEnum(value, MusicSkipBehavior.self) { Defaults[.musicSkipBehavior] = $0 }
        case "media.enableSneakPeek": return setBool(value) { Defaults[.enableSneakPeek] = $0 }
        case "media.showSneakPeekOnTrackChange": return setBool(value) { Defaults[.showSneakPeekOnTrackChange] = $0 }
        case "media.sneakPeekStyles": return setStringEnum(value, SneakPeekStyle.self) { Defaults[.sneakPeekStyles] = $0 }
        case "media.waitInterval": return setDouble(value) { Defaults[.waitInterval] = $0 }
        case "media.enableLyrics": return setBool(value) { Defaults[.enableLyrics] = $0 }
        case "media.showLiveCanvasInDynamicIsland": return setBool(value) { Defaults[.showLiveCanvasInDynamicIsland] = $0 }
        case "media.parallaxEffectIntensity": return setDouble(value) { Defaults[.parallaxEffectIntensity] = $0 }
        case "media.enableRealTimeWaveform": return setBool(value) { Defaults[.enableRealTimeWaveform] = $0 }
        case "media.enableLockScreenMediaWidget": return setBool(value) { Defaults[.enableLockScreenMediaWidget] = $0 }
        case "media.lockScreenShowAppIcon": return setBool(value) { Defaults[.lockScreenShowAppIcon] = $0 }
        case "media.lockScreenPanelShowsBorder": return setBool(value) { Defaults[.lockScreenPanelShowsBorder] = $0 }
        case "media.lockScreenPanelUsesBlur": return setBool(value) { Defaults[.lockScreenPanelUsesBlur] = $0 }
        case "media.lockScreenMusicAlbumParallaxEnabled": return setBool(value) { Defaults[.lockScreenMusicAlbumParallaxEnabled] = $0 }
        case "media.lockScreenMusicFullscreenArtworkEnabled": return setBool(value) { Defaults[.lockScreenMusicFullscreenArtworkEnabled] = $0 }

        case "stats.statsStopWhenNotchCloses": return setBool(value) { Defaults[.statsStopWhenNotchCloses] = $0 }
        case "stats.statsUpdateInterval": return setDouble(value) { Defaults[.statsUpdateInterval] = $0 }
        case "stats.showCpuGraph": return setBool(value) { Defaults[.showCpuGraph] = $0 }
        case "stats.showMemoryGraph": return setBool(value) { Defaults[.showMemoryGraph] = $0 }
        case "stats.showGpuGraph": return setBool(value) { Defaults[.showGpuGraph] = $0 }
        case "stats.showNetworkGraph": return setBool(value) { Defaults[.showNetworkGraph] = $0 }
        case "stats.showDiskGraph": return setBool(value) { Defaults[.showDiskGraph] = $0 }
        case "stats.cpuTemperatureUnit": return setStringEnum(value, LockScreenWeatherTemperatureUnit.self) { Defaults[.cpuTemperatureUnit] = $0 }

        case "timer.timerDisplayMode": return setStringEnum(value, TimerDisplayMode.self) { Defaults[.timerDisplayMode] = $0 }
        case "timer.mirrorSystemTimer": return setBool(value) { Defaults[.mirrorSystemTimer] = $0 }
        case "timer.timerControlWindowEnabled": return setBool(value) { Defaults[.timerControlWindowEnabled] = $0 }
        case "timer.showTimerPresetsInNotchTab": return setBool(value) { Defaults[.showTimerPresetsInNotchTab] = $0 }
        case "timer.timerIconColorMode": return setStringEnum(value, TimerIconColorMode.self) { Defaults[.timerIconColorMode] = $0 }
        case "timer.timerSolidColor": return setColor(value) { Defaults[.timerSolidColor] = $0 }
        case "timer.timerShowsCountdown": return setBool(value) { Defaults[.timerShowsCountdown] = $0 }
        case "timer.timerShowsLabel": return setBool(value) { Defaults[.timerShowsLabel] = $0 }
        case "timer.timerShowsProgress": return setBool(value) { Defaults[.timerShowsProgress] = $0 }
        case "timer.timerProgressStyle": return setStringEnum(value, TimerProgressStyle.self) { Defaults[.timerProgressStyle] = $0 }
        case "timer.enableLockScreenTimerWidget": return setBool(value) { Defaults[.enableLockScreenTimerWidget] = $0 }
        case "timer.lockScreenTimerWidgetUsesBlur": return setBool(value) { Defaults[.lockScreenTimerWidgetUsesBlur] = $0 }
        case "timer.lockScreenTimerGlassStyle": return setStringEnum(value, LockScreenGlassStyle.self) { Defaults[.lockScreenTimerGlassStyle] = $0 }
        case "timer.lockScreenTimerGlassCustomizationMode": return setStringEnum(value, LockScreenGlassCustomizationMode.self) { Defaults[.lockScreenTimerGlassCustomizationMode] = $0 }
        case "timer.lockScreenTimerLiquidGlassVariant": return setIntEnum(value, LiquidGlassVariant.self) { Defaults[.lockScreenTimerLiquidGlassVariant] = $0 }

        case "clipboard.showClipboardIcon": return setBool(value) { Defaults[.showClipboardIcon] = $0 }
        case "clipboard.clipboardDisplayMode": return setStringEnum(value, ClipboardDisplayMode.self) { Defaults[.clipboardDisplayMode] = $0 }
        case "clipboard.clipboardHistorySize": return setInt(value) { Defaults[.clipboardHistorySize] = $0 }

        case "colorPicker.showColorPickerIcon": return setBool(value) { Defaults[.showColorPickerIcon] = $0 }
        case "colorPicker.colorPickerDisplayMode": return setStringEnum(value, ColorPickerDisplayMode.self) { Defaults[.colorPickerDisplayMode] = $0 }
        case "colorPicker.colorHistorySize": return setInt(value) { Defaults[.colorHistorySize] = $0 }
        case "colorPicker.showColorFormats": return setBool(value) { Defaults[.showColorFormats] = $0 }

        case "calendar.hideCompletedReminders": return setBool(value) { Defaults[.hideCompletedReminders] = $0 }
        case "calendar.showFullEventTitles": return setBool(value) { Defaults[.showFullEventTitles] = $0 }
        case "calendar.autoScrollToNextEvent": return setBool(value) { Defaults[.autoScrollToNextEvent] = $0 }
        case "calendar.hideAllDayEvents": return setBool(value) { Defaults[.hideAllDayEvents] = $0 }
        case "calendar.enableReminderLiveActivity": return setBool(value) { Defaults[.enableReminderLiveActivity] = $0 }
        case "calendar.reminderPresentationStyle": return setStringEnum(value, ReminderPresentationStyle.self) { Defaults[.reminderPresentationStyle] = $0 }
        case "calendar.reminderLeadTime": return setInt(value) { Defaults[.reminderLeadTime] = $0 }
        case "calendar.reminderSneakPeekDuration": return setDouble(value) { Defaults[.reminderSneakPeekDuration] = $0 }
        case "calendar.enableLockScreenReminderWidget": return setBool(value) { Defaults[.enableLockScreenReminderWidget] = $0 }
        case "calendar.lockScreenReminderChipStyle": return setStringEnum(value, LockScreenReminderChipStyle.self) { Defaults[.lockScreenReminderChipStyle] = $0 }
        case "calendar.lockScreenShowCalendarEvent": return setBool(value) { Defaults[.lockScreenShowCalendarEvent] = $0 }
        case "calendar.lockScreenCalendarEventLookaheadWindow": return setString(value) { Defaults[.lockScreenCalendarEventLookaheadWindow] = $0 }
        case "calendar.lockScreenShowCalendarCountdown": return setBool(value) { Defaults[.lockScreenShowCalendarCountdown] = $0 }
        case "calendar.lockScreenShowCalendarEventEntireDuration": return setBool(value) { Defaults[.lockScreenShowCalendarEventEntireDuration] = $0 }
        case "calendar.lockScreenShowCalendarTimeRemaining": return setBool(value) { Defaults[.lockScreenShowCalendarTimeRemaining] = $0 }
        case "calendar.lockScreenShowCalendarStartTimeAfterBegins": return setBool(value) { Defaults[.lockScreenShowCalendarStartTimeAfterBegins] = $0 }
        case "calendar.enableThirdPartyCalendarApp": return setBool(value) { Defaults[.enableThirdPartyCalendarApp] = $0 }
        case "calendar.selectedCalendarApp": return setStringEnum(value, ThirdPartyCalendarApp.self) { Defaults[.selectedCalendarApp] = $0 }
        case "calendar.fantasticalDefaultView": return setStringEnum(value, FantasticalViewStyle.self) { Defaults[.fantasticalDefaultView] = $0 }

        case "shelf.openShelfByDefault": return setBool(value) { Defaults[.openShelfByDefault] = $0 }
        case "shelf.expandedDragDetection": return setBool(value) { Defaults[.expandedDragDetection] = $0 }
        case "shelf.copyOnDrag": return setBool(value) { Defaults[.copyOnDrag] = $0 }
        case "shelf.autoRemoveShelfItems": return setBool(value) { Defaults[.autoRemoveShelfItems] = $0 }
        case "shelf.quickShareProvider": return setString(value) { Defaults[.quickShareProvider] = $0 }
        case "shelf.localSendDevicePickerGlassMode": return setStringEnum(value, LockScreenGlassCustomizationMode.self) { Defaults[.localSendDevicePickerGlassMode] = $0 }
        case "shelf.localSendDevicePickerLiquidGlassVariant": return setIntEnum(value, LiquidGlassVariant.self) { Defaults[.localSendDevicePickerLiquidGlassVariant] = $0 }

        case "privacy.showDoNotDisturbLabel": return setBool(value) { Defaults[.showDoNotDisturbLabel] = $0 }
        case "privacy.focusIndicatorNonPersistent": return setBool(value) { Defaults[.focusIndicatorNonPersistent] = $0 }
        case "privacy.enableCapsLockIndicator": return setBool(value) { Defaults[.enableCapsLockIndicator] = $0 }
        case "privacy.capsLockIndicatorTintMode": return setStringEnum(value, CapsLockIndicatorTintMode.self) { Defaults[.capsLockIndicatorTintMode] = $0 }
        case "privacy.showCapsLockLabel": return setBool(value) { Defaults[.showCapsLockLabel] = $0 }

        case "recording.hideFromScreenCapture": return setBool(value) { Defaults[.hideDynamicIslandFromScreenCapture] = $0 }
        case "focus.focusIndicatorNonPersistent": return setBool(value) { Defaults[.focusIndicatorNonPersistent] = $0 }
        case "focus.showDoNotDisturbLabel": return setBool(value) { Defaults[.showDoNotDisturbLabel] = $0 }
        case "focus.focusMonitoringMode": return setStringEnum(value, FocusMonitoringMode.self) { Defaults[.focusMonitoringMode] = $0 }

        case "battery.showBatteryPercentage": return setBool(value) { Defaults[.showBatteryPercentage] = $0 }
        case "battery.showPowerStatusIcons": return setBool(value) { Defaults[.showPowerStatusIcons] = $0 }
        case "battery.playLowBatteryAlertSound": return setBool(value) { Defaults[.playLowBatteryAlertSound] = $0 }
        case "battery.showChargingBatteryHUD": return setBool(value) { Defaults[.showChargingBatteryHUD] = $0 }
        case "battery.showLowBatteryHUD": return setBool(value) { Defaults[.showLowBatteryHUD] = $0 }
        case "battery.showFullBatteryHUD": return setBool(value) { Defaults[.showFullBatteryHUD] = $0 }
        case "battery.chargingBatteryHUDDuration": return setInt(value) { Defaults[.chargingBatteryHUDDuration] = $0 }
        case "battery.lowBatteryHUDDuration": return setInt(value) { Defaults[.lowBatteryHUDDuration] = $0 }
        case "battery.fullBatteryHUDDuration": return setInt(value) { Defaults[.fullBatteryHUDDuration] = $0 }
        case "battery.lowBatteryHUDThreshold": return setInt(value) { Defaults[.lowBatteryHUDThreshold] = $0 }
        case "battery.fullBatteryHUDThreshold": return setInt(value) { Defaults[.fullBatteryHUDThreshold] = $0 }
        case "battery.lowBatteryHUDStyle": return setStringEnum(value, BatteryNotificationStyle.self) { Defaults[.lowBatteryHUDStyle] = $0 }
        case "battery.fullBatteryHUDStyle": return setStringEnum(value, BatteryNotificationStyle.self) { Defaults[.fullBatteryHUDStyle] = $0 }

        case "bluetooth.useCircularBluetoothBatteryIndicator": return setBool(value) { Defaults[.useCircularBluetoothBatteryIndicator] = $0 }
        case "bluetooth.showBluetoothBatteryPercentageText": return setBool(value) { Defaults[.showBluetoothBatteryPercentageText] = $0 }
        case "bluetooth.showBluetoothDeviceNameMarquee": return setBool(value) { Defaults[.showBluetoothDeviceNameMarquee] = $0 }
        case "bluetooth.useBluetoothHUD3DIcon": return setBool(value) { Defaults[.useBluetoothHUD3DIcon] = $0 }
        case "bluetooth.useColorCodedBatteryDisplay": return setBool(value) { Defaults[.useColorCodedBatteryDisplay] = $0 }

        case "downloads.selectedDownloadIndicatorStyle": return setStringEnum(value, DownloadIndicatorStyle.self) { Defaults[.selectedDownloadIndicatorStyle] = $0 }
        case "downloads.selectedDownloadIconStyle": return setStringEnum(value, DownloadIconStyle.self) { Defaults[.selectedDownloadIconStyle] = $0 }

        case "osd.enableVolumeHUD": return setBool(value) { Defaults[.enableVolumeHUD] = $0 }
        case "osd.enableBrightnessHUD": return setBool(value) { Defaults[.enableBrightnessHUD] = $0 }
        case "osd.enableKeyboardBacklightHUD": return setBool(value) { Defaults[.enableKeyboardBacklightHUD] = $0 }
        case "osd.playVolumeChangeFeedback": return setBool(value) { Defaults[.playVolumeChangeFeedback] = $0 }
        case "osd.useColorCodedVolumeDisplay": return setBool(value) { Defaults[.useColorCodedVolumeDisplay] = $0 }
        case "osd.useSmoothColorGradient": return setBool(value) { Defaults[.useSmoothColorGradient] = $0 }
        case "osd.showProgressPercentages": return setBool(value) { Defaults[.showProgressPercentages] = $0 }
        case "osd.inlineHUD": return setBool(value) { Defaults[.inlineHUD] = $0 }
        case "osd.progressBarStyle": return setStringEnum(value, ProgressBarStyle.self) { Defaults[.progressBarStyle] = $0 }
        case "osd.systemEventIndicatorShadow": return setBool(value) { Defaults[.systemEventIndicatorShadow] = $0 }
        case "osd.systemEventIndicatorUseAccent": return setBool(value) { Defaults[.systemEventIndicatorUseAccent] = $0 }
        case "osd.enableCustomOSD": return setBool(value) { Defaults[.enableCustomOSD] = $0 }
        case "osd.enableVerticalHUD": return setBool(value) { Defaults[.enableVerticalHUD] = $0 }
        case "osd.enableCircularHUD": return setBool(value) { Defaults[.enableCircularHUD] = $0 }
        case "osd.osdMaterial": return setStringEnum(value, OSDMaterial.self) { Defaults[.osdMaterial] = $0 }
        case "osd.osdIconColorStyle": return setStringEnum(value, OSDIconColorStyle.self) { Defaults[.osdIconColorStyle] = $0 }
        case "osd.verticalHUDPosition": return setString(value) { Defaults[.verticalHUDPosition] = $0 }
        case "osd.verticalHUDShowValue": return setBool(value) { Defaults[.verticalHUDShowValue] = $0 }
        case "osd.verticalHUDInteractive": return setBool(value) { Defaults[.verticalHUDInteractive] = $0 }
        case "osd.verticalHUDUseAccentColor": return setBool(value) { Defaults[.verticalHUDUseAccentColor] = $0 }
        case "osd.verticalHUDWidth": return setDouble(value) { Defaults[.verticalHUDWidth] = CGFloat($0) }
        case "osd.verticalHUDHeight": return setDouble(value) { Defaults[.verticalHUDHeight] = CGFloat($0) }
        case "osd.verticalHUDPadding": return setDouble(value) { Defaults[.verticalHUDPadding] = CGFloat($0) }

        case "lockScreen.enableLockSounds": return setBool(value) { Defaults[.enableLockSounds] = $0 }
        case "lockScreen.lockScreenGlassStyle": return setStringEnum(value, LockScreenGlassStyle.self) { Defaults[.lockScreenGlassStyle] = $0 }
        case "lockScreen.lockScreenGlassCustomizationMode": return setStringEnum(value, LockScreenGlassCustomizationMode.self) { Defaults[.lockScreenGlassCustomizationMode] = $0 }
        case "lockScreen.lockScreenMusicLiquidGlassVariant": return setIntEnum(value, LiquidGlassVariant.self) { Defaults[.lockScreenMusicLiquidGlassVariant] = $0 }
        case "lockScreen.enableLockScreenWeatherWidget": return setBool(value) { Defaults[.enableLockScreenWeatherWidget] = $0 }
        case "lockScreen.lockScreenWeatherWidgetStyle": return setStringEnum(value, LockScreenWeatherWidgetStyle.self) { Defaults[.lockScreenWeatherWidgetStyle] = $0 }
        case "lockScreen.lockScreenWeatherProviderSource": return setStringEnum(value, LockScreenWeatherProviderSource.self) { Defaults[.lockScreenWeatherProviderSource] = $0 }
        case "lockScreen.lockScreenWeatherTemperatureUnit": return setStringEnum(value, LockScreenWeatherTemperatureUnit.self) { Defaults[.lockScreenWeatherTemperatureUnit] = $0 }
        case "lockScreen.lockScreenWeatherShowsLocation": return setBool(value) { Defaults[.lockScreenWeatherShowsLocation] = $0 }
        case "lockScreen.lockScreenWeatherShowsSunrise": return setBool(value) { Defaults[.lockScreenWeatherShowsSunrise] = $0 }
        case "lockScreen.lockScreenWeatherShowsAQI": return setBool(value) { Defaults[.lockScreenWeatherShowsAQI] = $0 }
        case "lockScreen.lockScreenWeatherAQIScale": return setStringEnum(value, LockScreenWeatherAirQualityScale.self) { Defaults[.lockScreenWeatherAQIScale] = $0 }
        case "lockScreen.lockScreenWeatherUsesGaugeTint": return setBool(value) { Defaults[.lockScreenWeatherUsesGaugeTint] = $0 }
        case "lockScreen.lockScreenBatteryShowsBatteryGauge": return setBool(value) { Defaults[.lockScreenBatteryShowsBatteryGauge] = $0 }
        case "lockScreen.lockScreenBatteryUsesLaptopSymbol": return setBool(value) { Defaults[.lockScreenBatteryUsesLaptopSymbol] = $0 }
        case "lockScreen.lockScreenBatteryShowsCharging": return setBool(value) { Defaults[.lockScreenBatteryShowsCharging] = $0 }
        case "lockScreen.lockScreenBatteryShowsChargingPercentage": return setBool(value) { Defaults[.lockScreenBatteryShowsChargingPercentage] = $0 }
        case "lockScreen.lockScreenBatteryShowsBluetooth": return setBool(value) { Defaults[.lockScreenBatteryShowsBluetooth] = $0 }

        case "extensions.enableExtensionDiagnosticsLogging": return setBool(value) { Defaults[.extensionDiagnosticsLoggingEnabled] = $0 }
        case "extensions.enableExtensionNotchMinimalisticOverrides": return setBool(value) { Defaults[.enableExtensionNotchMinimalisticOverrides] = $0 }
        case "extensions.enableExtensionNotchInteractiveWebViews": return setBool(value) { Defaults[.enableExtensionNotchInteractiveWebViews] = $0 }
        case "extensions.enableExtensionFileSharing": return setBool(value) { Defaults[.enableExtensionFileSharing] = $0 }
        case "extensions.extensionLiveActivityCapacity": return setInt(value) { Defaults[.extensionLiveActivityCapacity] = $0 }
        case "extensions.extensionLockScreenWidgetCapacity": return setInt(value) { Defaults[.extensionLockScreenWidgetCapacity] = $0 }
        case "extensions.extensionNotchExperienceCapacity": return setInt(value) { Defaults[.extensionNotchExperienceCapacity] = $0 }

        case "screenAssistant.screenAssistantDisplayMode": return setStringEnum(value, ScreenAssistantDisplayMode.self) { Defaults[.screenAssistantDisplayMode] = $0 }
        case "screenAssistant.selectedAIProvider": return setStringEnum(value, AIModelProvider.self) { Defaults[.selectedAIProvider] = $0 }
        case "screenAssistant.enableThinkingMode": return setBool(value) { Defaults[.enableThinkingMode] = $0 }
        case "screenAssistant.localModelEndpoint": return setString(value) { Defaults[.localModelEndpoint] = $0 }

        default:
            return false
        }
    }
}

private extension AtollSettingsBridge {
    static let catalog: [AtollSettingsTabID: [AtollSettingGroupDescriptor]] = [
        .island: [
            group("Behavior", [
                toggle("island.extendHoverArea", "Extend hover area", "Make it easier to open the island near the notch."),
                slider("island.minimumHoverDuration", "Minimum hover duration", "Delay before hover opens the island.", 0, 1, 0.1, "s"),
                toggle("island.enableHaptics", "Enable haptics", "Use feedback on supported trackpads."),
                toggle("island.hideFromScreenCapture", "Hide during screenshots", "Avoid capturing the island in screenshots and recordings.")
            ]),
            group("External Displays", [
                toggle("island.hideNonNotchUntilHover", "Hide until hovered", "Keep the floating pill hidden on non-notch displays until the pointer approaches.")
            ])
        ],
        .appearance: [
            group("Island Chrome", [
                toggle("appearance.settingsIconInNotch", "Settings icon in notch", "Show the settings affordance inside the island."),
                toggle("appearance.enableShadow", "Enable window shadow", "Add depth around the expanded island."),
                toggle("appearance.cornerRadiusScaling", "Corner radius scaling", "Scale corner radii with the current island size."),
                toggle("appearance.useModernCloseAnimation", "Use simpler close animation", "Use the newer close animation path.")
            ]),
            group("Visual Effects", [
                toggle("appearance.coloredSpectrogram", "Colored spectrograms", "Tint media visualizers with richer colors."),
                toggle("appearance.playerColorTinting", "Player color tinting", "Tint player controls from artwork."),
                toggle("appearance.lightingEffect", "Lighting effect", "Enable ambient lighting around media artwork."),
                picker("appearance.sliderColor", "Slider color", "Choose the player slider color source.", enumOptions(SliderColorEnum.self) { $0.localizedName })
            ]),
            group("Mirror & Idle", [
                toggle("appearance.showMirror", "Dynamic mirror", "Show the camera mirror surface."),
                picker("appearance.mirrorShape", "Mirror shape", "Choose the mirror preview shape.", fixedOptions([("Rectangular", "Rectangular"), ("Circular", "Circular")])),
                toggle("appearance.showNotHumanFace", "Idle animation", "Show the idle face animation when inactive.")
            ])
        ],
        .media: [
            group("Source & Visibility", [
                picker("media.mediaController", "Music source", "Choose the playback metadata provider.", enumOptions(MediaControllerType.self) { $0.localizedName }),
                toggle("media.autoHideInactiveNotchMediaPlayer", "Auto-hide inactive player", "Hide placeholder media when playback is inactive.")
            ]),
            group("Controls", [
                toggle("media.showShuffleAndRepeat", "Customizable controls", "Allow custom media button layout."),
                toggle("media.showMediaOutputControl", "Change Media Output control", "Show the output route button."),
                toggle("media.musicControlWindowEnabled", "Floating media controls", "Show a small media control window beside the island."),
                picker("media.musicSkipBehavior", "Skip buttons", "Choose previous/next track or ten-second skip.", enumOptions(MusicSkipBehavior.self) { $0.displayName })
            ]),
            group("Live Activity", [
                toggle("media.enableSneakPeek", "Enable sneak peek", "Show media details briefly below the notch."),
                toggle("media.showSneakPeekOnTrackChange", "Sneak peek on playback changes", "Trigger sneak peek when tracks change."),
                picker("media.sneakPeekStyles", "Sneak Peek style", nil, enumOptions(SneakPeekStyle.self)),
                slider("media.waitInterval", "Media inactivity timeout", nil, 0, 10, 1, "s"),
                toggle("media.enableLyrics", "Enable lyrics", "Allow lyric surfaces when the media source supports them."),
                toggle("media.showLiveCanvasInDynamicIsland", "Show live canvas", "Use moving artwork/canvas inside the island."),
                slider("media.parallaxEffectIntensity", "Parallax intensity", nil, 0, 12, 1, nil),
                toggle("media.enableRealTimeWaveform", "Real-time waveform", "Use the live audio spectrum visualizer.")
            ]),
            group("Lock Screen Media", [
                toggle("media.enableLockScreenMediaWidget", "Show lock screen media panel", nil),
                toggle("media.lockScreenShowAppIcon", "Show media app icon", nil),
                toggle("media.lockScreenPanelShowsBorder", "Show panel border", nil),
                toggle("media.lockScreenPanelUsesBlur", "Enable media panel blur", nil),
                toggle("media.lockScreenMusicAlbumParallaxEnabled", "Album art parallax", nil),
                toggle("media.lockScreenMusicFullscreenArtworkEnabled", "Fullscreen artwork on right-click", nil)
            ])
        ],
        .stats: [
            group("Monitoring", [
                toggle("stats.statsStopWhenNotchCloses", "Stop after closing notch", "Pause monitoring shortly after the island closes."),
                slider("stats.statsUpdateInterval", "Update interval", "Metric refresh interval.", 1, 60, 1, "s")
            ]),
            group("Graph Visibility", [
                toggle("stats.showCpuGraph", "CPU usage", nil),
                picker("stats.cpuTemperatureUnit", "Temperature unit", nil, enumOptions(LockScreenWeatherTemperatureUnit.self)),
                toggle("stats.showMemoryGraph", "Memory usage", nil),
                toggle("stats.showGpuGraph", "GPU usage", nil),
                toggle("stats.showNetworkGraph", "Network activity", nil),
                toggle("stats.showDiskGraph", "Disk I/O", nil)
            ])
        ],
        .timer: [
            group("Behavior", [
                picker("timer.timerDisplayMode", "Timer controls appear as", nil, enumOptions(TimerDisplayMode.self) { $0.displayName }),
                toggle("timer.mirrorSystemTimer", "Mirror macOS Clock timers", nil),
                toggle("timer.timerControlWindowEnabled", "Timer control window", nil),
                toggle("timer.showTimerPresetsInNotchTab", "Show presets in tab", nil)
            ]),
            group("Appearance", [
                picker("timer.timerIconColorMode", "Timer tint", nil, enumOptions(TimerIconColorMode.self) { $0.displayName }),
                color("timer.timerSolidColor", "Solid colour", nil),
                toggle("timer.timerShowsCountdown", "Show countdown", nil),
                toggle("timer.timerShowsLabel", "Show label", nil),
                toggle("timer.timerShowsProgress", "Show progress", nil),
                picker("timer.timerProgressStyle", "Progress style", nil, enumOptions(TimerProgressStyle.self) { $0.localizedName })
            ]),
            group("Lock Screen Timer", [
                toggle("timer.enableLockScreenTimerWidget", "Show lock screen timer widget", nil),
                toggle("timer.lockScreenTimerWidgetUsesBlur", "Use blur", nil),
                picker("timer.lockScreenTimerGlassStyle", "Timer glass material", nil, enumOptions(LockScreenGlassStyle.self) { $0.localizedName }),
                picker("timer.lockScreenTimerGlassCustomizationMode", "Timer liquid mode", nil, enumOptions(LockScreenGlassCustomizationMode.self) { $0.localizedName }),
                slider("timer.lockScreenTimerLiquidGlassVariant", "Liquid variant", nil, Double(LiquidGlassVariant.supportedRange.lowerBound), Double(LiquidGlassVariant.supportedRange.upperBound), 1, nil)
            ])
        ],
        .clipboard: [
            group("Clipboard", [
                toggle("clipboard.showClipboardIcon", "Show clipboard icon", nil),
                picker("clipboard.clipboardDisplayMode", "Display mode", nil, enumOptions(ClipboardDisplayMode.self) { $0.displayName }),
                picker("clipboard.clipboardHistorySize", "History size", nil, fixedOptions([("3", "3 items"), ("5", "5 items"), ("7", "7 items"), ("10", "10 items")]))
            ])
        ],
        .colorPicker: [
            group("Color Picker", [
                toggle("colorPicker.showColorPickerIcon", "Show color picker icon", nil),
                picker("colorPicker.colorPickerDisplayMode", "Display mode", nil, enumOptions(ColorPickerDisplayMode.self) { $0.displayName }),
                picker("colorPicker.colorHistorySize", "History size", nil, fixedOptions([("5", "5 colors"), ("10", "10 colors"), ("15", "15 colors"), ("20", "20 colors")])),
                toggle("colorPicker.showColorFormats", "Show all color formats", nil)
            ])
        ],
        .calendar: [
            group("Event List", [
                toggle("calendar.hideCompletedReminders", "Hide completed reminders", nil),
                toggle("calendar.showFullEventTitles", "Show full event titles", nil),
                toggle("calendar.autoScrollToNextEvent", "Auto-scroll to next event", nil),
                toggle("calendar.hideAllDayEvents", "Hide all-day events", nil)
            ]),
            group("Reminder Live Activity", [
                toggle("calendar.enableReminderLiveActivity", "Enable reminder live activity", nil),
                picker("calendar.reminderPresentationStyle", "Countdown style", nil, enumOptions(ReminderPresentationStyle.self) { $0.displayName }),
                slider("calendar.reminderLeadTime", "Notify before", nil, 1, 60, 1, "min"),
                slider("calendar.reminderSneakPeekDuration", "Sneak peek duration", nil, 3, 20, 1, "s"),
                toggle("calendar.enableLockScreenReminderWidget", "Show lock screen reminder", nil),
                picker("calendar.lockScreenReminderChipStyle", "Chip color", nil, enumOptions(LockScreenReminderChipStyle.self) { $0.localizedName })
            ]),
            group("Calendar Widget", [
                toggle("calendar.lockScreenShowCalendarEvent", "Show next calendar event", nil),
                picker("calendar.lockScreenCalendarEventLookaheadWindow", "Show events within next", nil, calendarLookaheadOptions),
                toggle("calendar.lockScreenShowCalendarCountdown", "Show countdown", nil),
                toggle("calendar.lockScreenShowCalendarEventEntireDuration", "Show event for entire duration", nil),
                toggle("calendar.lockScreenShowCalendarTimeRemaining", "Show time remaining", nil),
                toggle("calendar.lockScreenShowCalendarStartTimeAfterBegins", "Show start time after event begins", nil)
            ]),
            group("Third-party Calendar", [
                toggle("calendar.enableThirdPartyCalendarApp", "Enable third-party calendar launch", nil),
                picker("calendar.selectedCalendarApp", "Calendar app", nil, enumOptions(ThirdPartyCalendarApp.self) { $0.displayName }),
                picker("calendar.fantasticalDefaultView", "Fantastical default view", nil, enumOptions(FantasticalViewStyle.self) { $0.displayName })
            ])
        ],
        .shelf: [
            group("Shelf", [
                toggle("shelf.openShelfByDefault", "Open shelf tab by default", nil),
                toggle("shelf.expandedDragDetection", "Expanded drag detection area", nil),
                toggle("shelf.copyOnDrag", "Copy items on drag", nil),
                toggle("shelf.autoRemoveShelfItems", "Remove from shelf after dragging", nil)
            ]),
            group("Quick Share", [
                picker("shelf.quickShareProvider", "Quick Share service", nil, fixedOptions([("AirDrop", "AirDrop"), ("LocalSend", "LocalSend")])),
                picker("shelf.localSendDevicePickerGlassMode", "LocalSend picker style", nil, enumOptions(LockScreenGlassCustomizationMode.self) { $0.localizedName }),
                slider("shelf.localSendDevicePickerLiquidGlassVariant", "LocalSend liquid variant", nil, Double(LiquidGlassVariant.supportedRange.lowerBound), Double(LiquidGlassVariant.supportedRange.upperBound), 1, nil)
            ])
        ],
        .privacy: [
            group("Privacy Indicators", [
                toggle("privacy.enableCapsLockIndicator", "Show Caps Lock indicator", nil),
                picker("privacy.capsLockIndicatorTintMode", "Caps Lock tint", nil, enumOptions(CapsLockIndicatorTintMode.self) { $0.displayName }),
                toggle("privacy.showCapsLockLabel", "Show Caps Lock label", nil)
            ]),
            group("Shared Focus Display", [
                toggle("privacy.showDoNotDisturbLabel", "Show Focus label", nil),
                toggle("privacy.focusIndicatorNonPersistent", "Show Focus as brief toast", nil)
            ])
        ],
        .recording: [
            group("Recording Indicator", [
                toggle("recording.hideFromScreenCapture", "Hide island during screen capture", "Keep the island out of screenshots and recordings.")
            ])
        ],
        .focus: [
            group("Focus Indicator", [
                picker("focus.focusMonitoringMode", "Focus monitoring mode", nil, enumOptions(FocusMonitoringMode.self) { $0.displayName }),
                toggle("focus.showDoNotDisturbLabel", "Show Focus label", nil),
                toggle("focus.focusIndicatorNonPersistent", "Show Focus as brief toast", nil)
            ])
        ],
        .battery: [
            group("Battery Information", [
                toggle("battery.showBatteryPercentage", "Show battery percentage", nil),
                toggle("battery.showPowerStatusIcons", "Show power status icons", nil),
                toggle("battery.playLowBatteryAlertSound", "Play low battery alert sound", nil)
            ]),
            group("Battery HUDs", [
                toggle("battery.showChargingBatteryHUD", "Charging HUD", nil),
                toggle("battery.showLowBatteryHUD", "Low battery HUD", nil),
                toggle("battery.showFullBatteryHUD", "Fully charged HUD", nil),
                slider("battery.chargingBatteryHUDDuration", "Charging duration", nil, 1, 10, 1, "s"),
                slider("battery.lowBatteryHUDDuration", "Low battery duration", nil, 1, 10, 1, "s"),
                slider("battery.fullBatteryHUDDuration", "Full battery duration", nil, 1, 10, 1, "s")
            ]),
            group("Thresholds", [
                picker("battery.lowBatteryHUDStyle", "Low battery style", nil, enumOptions(BatteryNotificationStyle.self) { $0.title }),
                slider("battery.lowBatteryHUDThreshold", "Low battery threshold", nil, 5, 30, 1, "%"),
                picker("battery.fullBatteryHUDStyle", "Full battery style", nil, enumOptions(BatteryNotificationStyle.self) { $0.title }),
                slider("battery.fullBatteryHUDThreshold", "Full charge threshold", nil, 80, 100, 1, "%")
            ])
        ],
        .bluetooth: [
            group("Bluetooth Audio Devices", [
                toggle("bluetooth.useCircularBluetoothBatteryIndicator", "Use circular battery indicator", nil),
                toggle("bluetooth.showBluetoothBatteryPercentageText", "Show battery percentage text", nil),
                toggle("bluetooth.showBluetoothDeviceNameMarquee", "Scroll device name", nil),
                toggle("bluetooth.useBluetoothHUD3DIcon", "Use 3D Bluetooth HUD icon", nil)
            ]),
            group("Battery Indicator Styling", [
                toggle("bluetooth.useColorCodedBatteryDisplay", "Color-coded battery display", nil)
            ])
        ],
        .downloads: [
            group("Download Detection", [
                picker("downloads.selectedDownloadIndicatorStyle", "Download indicator style", nil, fixedOptions([("Progress", "Progress"), ("Percentage", "Percentage"), ("Circle", "Circle")])),
                picker("downloads.selectedDownloadIconStyle", "Download icon style", nil, fixedOptions([("Only app icon", "Only app icon"), ("Only download icon", "Only download icon"), ("Icon and app icon", "Icon and app icon")]))
            ])
        ],
        .osd: [
            group("Controls", [
                toggle("osd.enableVolumeHUD", "Volume HUD", nil),
                toggle("osd.enableBrightnessHUD", "Brightness HUD", nil),
                toggle("osd.enableKeyboardBacklightHUD", "Keyboard Backlight HUD", nil),
                toggle("osd.playVolumeChangeFeedback", "Play feedback when volume changes", nil)
            ]),
            group("Progress Bars", [
                toggle("osd.useColorCodedVolumeDisplay", "Color-coded volume display", nil),
                toggle("osd.useSmoothColorGradient", "Smooth color transitions", nil),
                toggle("osd.showProgressPercentages", "Show percentages beside progress bars", nil),
                picker("osd.progressBarStyle", "Progressbar style", nil, enumOptions(ProgressBarStyle.self))
            ]),
            group("Modes", [
                toggle("osd.inlineHUD", "Inline HUD style", nil),
                toggle("osd.systemEventIndicatorShadow", "Enable glowing effect", nil),
                toggle("osd.systemEventIndicatorUseAccent", "Use accent color", nil),
                toggle("osd.enableCustomOSD", "Enable Custom OSD", nil),
                toggle("osd.enableVerticalHUD", "Enable Vertical Bar", nil),
                toggle("osd.enableCircularHUD", "Enable Circular HUD", nil),
                picker("osd.osdMaterial", "Material", nil, enumOptions(OSDMaterial.self)),
                picker("osd.osdIconColorStyle", "Icon & Progress Color", nil, enumOptions(OSDIconColorStyle.self))
            ]),
            group("Vertical Bar", [
                picker("osd.verticalHUDPosition", "HUD position", nil, fixedOptions([("left", "Left"), ("right", "Right")])),
                toggle("osd.verticalHUDShowValue", "Show value", nil),
                toggle("osd.verticalHUDInteractive", "Interactive", nil),
                toggle("osd.verticalHUDUseAccentColor", "Use accent color", nil),
                slider("osd.verticalHUDWidth", "Width", nil, 24, 80, 2, "pt"),
                slider("osd.verticalHUDHeight", "Height", nil, 100, 500, 10, "pt"),
                slider("osd.verticalHUDPadding", "Padding", nil, 0, 100, 4, "pt")
            ])
        ],
        .lockScreenWidgets: [
            group("Lock Screen", [
                toggle("lockScreen.enableLockSounds", "Play lock/unlock sounds", nil),
                picker("lockScreen.lockScreenGlassStyle", "Material", nil, enumOptions(LockScreenGlassStyle.self) { $0.localizedName }),
                picker("lockScreen.lockScreenGlassCustomizationMode", "Glass mode", nil, enumOptions(LockScreenGlassCustomizationMode.self) { $0.localizedName }),
                slider("lockScreen.lockScreenMusicLiquidGlassVariant", "Liquid Glass variant", nil, Double(LiquidGlassVariant.supportedRange.lowerBound), Double(LiquidGlassVariant.supportedRange.upperBound), 1, nil)
            ]),
            group("Weather Widget", [
                toggle("lockScreen.enableLockScreenWeatherWidget", "Show lock screen weather", nil),
                picker("lockScreen.lockScreenWeatherWidgetStyle", "Layout", nil, enumOptions(LockScreenWeatherWidgetStyle.self) { $0.localizedName }),
                picker("lockScreen.lockScreenWeatherProviderSource", "Weather data provider", nil, enumOptions(LockScreenWeatherProviderSource.self) { $0.displayName }),
                picker("lockScreen.lockScreenWeatherTemperatureUnit", "Temperature unit", nil, enumOptions(LockScreenWeatherTemperatureUnit.self)),
                toggle("lockScreen.lockScreenWeatherShowsLocation", "Show location label", nil),
                toggle("lockScreen.lockScreenWeatherShowsSunrise", "Show sunrise", nil),
                toggle("lockScreen.lockScreenWeatherShowsAQI", "Show AQI widget", nil),
                picker("lockScreen.lockScreenWeatherAQIScale", "Air quality scale", nil, enumOptions(LockScreenWeatherAirQualityScale.self) { $0.displayName }),
                toggle("lockScreen.lockScreenWeatherUsesGaugeTint", "Use colored gauges", nil)
            ]),
            group("Battery Widget", [
                toggle("lockScreen.lockScreenBatteryShowsBatteryGauge", "Show battery indicator", nil),
                toggle("lockScreen.lockScreenBatteryUsesLaptopSymbol", "Use MacBook icon on battery", nil),
                toggle("lockScreen.lockScreenBatteryShowsCharging", "Show charging status", nil),
                toggle("lockScreen.lockScreenBatteryShowsChargingPercentage", "Show charging percentage", nil),
                toggle("lockScreen.lockScreenBatteryShowsBluetooth", "Show Bluetooth battery", nil)
            ])
        ],
        .extensionBridge: [
            group("Extensions", [
                toggle("extensions.enableExtensionNotchMinimalisticOverrides", "Allow minimalistic overrides", nil),
                toggle("extensions.enableExtensionNotchInteractiveWebViews", "Allow interactive web content", nil),
                toggle("extensions.enableExtensionFileSharing", "Allow extension file sharing", nil),
                toggle("extensions.enableExtensionDiagnosticsLogging", "Enable diagnostics logging", nil),
                slider("extensions.extensionLiveActivityCapacity", "Live activity capacity", nil, 1, 10, 1, nil),
                slider("extensions.extensionLockScreenWidgetCapacity", "Lock screen widget capacity", nil, 1, 10, 1, nil),
                slider("extensions.extensionNotchExperienceCapacity", "Notch experience capacity", nil, 1, 5, 1, nil)
            ])
        ],
        .screenAssistant: [
            group("Assistant", [
                picker("screenAssistant.screenAssistantDisplayMode", "Display mode", nil, enumOptions(ScreenAssistantDisplayMode.self) { $0.displayName }),
                picker("screenAssistant.selectedAIProvider", "Default provider", nil, enumOptions(AIModelProvider.self) { $0.displayName }),
                toggle("screenAssistant.enableThinkingMode", "Enable thinking mode", nil),
                text("screenAssistant.localModelEndpoint", "Local model endpoint", "Endpoint used by local model providers.")
            ])
        ]
    ]

    static let calendarLookaheadOptions = fixedOptions([
        ("15m", "15 mins"),
        ("30m", "30 mins"),
        ("1h", "1 hour"),
        ("3h", "3 hours"),
        ("6h", "6 hours"),
        ("12h", "12 hours"),
        ("rest_of_day", "Rest of the day"),
        ("all_time", "All time")
    ])

    static func group(_ title: String, _ settings: [AtollSettingDescriptor]) -> AtollSettingGroupDescriptor {
        AtollSettingGroupDescriptor(id: title, title: title, settings: settings)
    }

    static func toggle(_ id: String, _ title: String, _ description: String?) -> AtollSettingDescriptor {
        AtollSettingDescriptor(id: id, title: title, description: description, control: .toggle)
    }

    static func slider(
        _ id: String,
        _ title: String,
        _ description: String?,
        _ min: Double,
        _ max: Double,
        _ step: Double,
        _ unit: String?
    ) -> AtollSettingDescriptor {
        AtollSettingDescriptor(
            id: id,
            title: title,
            description: description,
            control: .slider(min: min, max: max, step: step, unit: unit)
        )
    }

    static func picker(
        _ id: String,
        _ title: String,
        _ description: String?,
        _ options: [AtollSettingOption]
    ) -> AtollSettingDescriptor {
        AtollSettingDescriptor(id: id, title: title, description: description, control: .picker(options))
    }

    static func text(_ id: String, _ title: String, _ description: String?) -> AtollSettingDescriptor {
        AtollSettingDescriptor(id: id, title: title, description: description, control: .text)
    }

    static func color(_ id: String, _ title: String, _ description: String?) -> AtollSettingDescriptor {
        AtollSettingDescriptor(id: id, title: title, description: description, control: .color)
    }

    static func fixedOptions(_ pairs: [(String, String)]) -> [AtollSettingOption] {
        pairs.map { AtollSettingOption(value: $0.0, title: $0.1) }
    }

    static func enumOptions<T: CaseIterable & RawRepresentable>(
        _ type: T.Type,
        title: (T) -> String
    ) -> [AtollSettingOption] where T.RawValue == String {
        T.allCases.map { AtollSettingOption(value: $0.rawValue, title: title($0)) }
    }

    static func enumOptions<T: CaseIterable & RawRepresentable>(
        _ type: T.Type
    ) -> [AtollSettingOption] where T.RawValue == String {
        T.allCases.map { AtollSettingOption(value: $0.rawValue, title: $0.rawValue) }
    }

    static func setBool(_ value: AtollSettingValue, assign: (Bool) -> Void) -> Bool {
        guard case .bool(let bool) = value else { return false }
        assign(bool)
        return true
    }

    static func setDouble(_ value: AtollSettingValue, assign: (Double) -> Void) -> Bool {
        switch value {
        case .double(let double):
            assign(double)
        case .int(let int):
            assign(Double(int))
        default:
            return false
        }
        return true
    }

    static func setInt(_ value: AtollSettingValue, assign: (Int) -> Void) -> Bool {
        switch value {
        case .int(let int):
            assign(int)
        case .double(let double):
            assign(Int(double.rounded()))
        case .string(let string):
            guard let int = Int(string) else { return false }
            assign(int)
        default:
            return false
        }
        return true
    }

    static func setString(_ value: AtollSettingValue, assign: (String) -> Void) -> Bool {
        guard case .string(let string) = value else { return false }
        assign(string)
        return true
    }

    static func setStringEnum<T: RawRepresentable>(
        _ value: AtollSettingValue,
        _ type: T.Type,
        assign: (T) -> Void
    ) -> Bool where T.RawValue == String {
        guard case .string(let rawValue) = value, let parsed = T(rawValue: rawValue) else { return false }
        assign(parsed)
        return true
    }

    static func setIntEnum<T: RawRepresentable>(
        _ value: AtollSettingValue,
        _ type: T.Type,
        assign: (T) -> Void
    ) -> Bool where T.RawValue == Int {
        let rawValue: Int
        switch value {
        case .int(let int):
            rawValue = int
        case .double(let double):
            rawValue = Int(double.rounded())
        default:
            return false
        }
        guard let parsed = T(rawValue: rawValue) else { return false }
        assign(parsed)
        return true
    }

    static func colorValue(_ color: Color) -> AtollSettingValue {
        let nsColor = NSColor(color)
        let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return .color(
            AtollSettingColor(
                red: normalizedColorComponent(resolved.redComponent),
                green: normalizedColorComponent(resolved.greenComponent),
                blue: normalizedColorComponent(resolved.blueComponent),
                opacity: normalizedColorComponent(resolved.alphaComponent)
            )
        )
    }

    static func setColor(_ value: AtollSettingValue, assign: (Color) -> Void) -> Bool {
        guard case .color(let color) = value else { return false }
        assign(
            Color(
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.opacity
            )
        )
        return true
    }

    static func normalizedColorComponent(_ component: CGFloat) -> Double {
        (Double(component) * 1_000_000).rounded() / 1_000_000
    }
}
