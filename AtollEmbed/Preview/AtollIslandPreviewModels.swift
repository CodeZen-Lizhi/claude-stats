import Foundation
import SwiftUI

public enum AtollIslandPreviewTab: String, CaseIterable, Identifiable, Sendable {
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

    public var title: String {
        switch self {
        case .island: "Island"
        case .appearance: "Appearance"
        case .media: "Media"
        case .stats: "Stats"
        case .timer: "Timer"
        case .clipboard: "Clipboard"
        case .colorPicker: "Color Picker"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .privacy: "Privacy"
        case .recording: "Recording"
        case .focus: "Focus"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .downloads: "Downloads"
        case .osd: "OSD"
        case .lockScreenWidgets: "Lock Widgets"
        case .extensionBridge: "Extensions"
        case .screenAssistant: "Screen Assistant"
        }
    }

    public var systemImage: String {
        switch self {
        case .island: "capsule.tophalf.filled"
        case .appearance: "paintpalette"
        case .media: "music.note"
        case .stats: "cpu"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard"
        case .colorPicker: "eyedropper"
        case .calendar: "calendar"
        case .shelf: "tray.fill"
        case .privacy: "web.camera"
        case .recording: "record.circle"
        case .focus: "moon"
        case .battery: "battery.75percent"
        case .bluetooth: "headphones"
        case .downloads: "arrow.down.circle"
        case .osd: "slider.horizontal.3"
        case .lockScreenWidgets: "lock.display"
        case .extensionBridge: "puzzlepiece.extension"
        case .screenAssistant: "sparkles"
        }
    }

    var isAlwaysAvailable: Bool {
        self == .island || self == .appearance
    }
}

public enum AtollIslandPreviewSizePreset: String, CaseIterable, Sendable {
    case compact
    case regular
    case large

    public var openDisplayWidth: CGFloat {
        switch self {
        case .compact: 350
        case .regular: 420
        case .large: 480
        }
    }

    public var openDisplayHeight: CGFloat {
        switch self {
        case .compact: 152
        case .regular: 176
        case .large: 196
        }
    }

    public var minimumDisplayWidth: CGFloat {
        190 + 16 + openDisplayWidth + 28
    }
}

public struct AtollIslandPreviewConfiguration: Equatable, Sendable {
    public var selectedTab: AtollIslandPreviewTab
    public var enabledTabs: Set<AtollIslandPreviewTab>
    public var sizePreset: AtollIslandPreviewSizePreset
    public var isFeatureEnabled: Bool
    public var hoverExpansionEnabled: Bool
    public var settings: AtollIslandPreviewSettings

    public init(
        selectedTab: AtollIslandPreviewTab,
        enabledTabs: Set<AtollIslandPreviewTab>,
        sizePreset: AtollIslandPreviewSizePreset,
        isFeatureEnabled: Bool,
        hoverExpansionEnabled: Bool,
        settings: AtollIslandPreviewSettings
    ) {
        self.selectedTab = selectedTab
        self.enabledTabs = enabledTabs
        self.sizePreset = sizePreset
        self.isFeatureEnabled = isFeatureEnabled
        self.hoverExpansionEnabled = hoverExpansionEnabled
        self.settings = settings
    }

    public var isSelectedTabEnabled: Bool {
        isFeatureEnabled && (selectedTab.isAlwaysAvailable || enabledTabs.contains(selectedTab))
    }
}

public struct AtollIslandPreviewSettings: Equatable, Sendable {
    public var externalDisplayStyle: String
    public var enableShadow: Bool
    public var cornerRadiusScaling: Bool
    public var settingsIconInNotch: Bool
    public var showMirror: Bool
    public var coloredSpectrogram: Bool
    public var playerColorTinting: Bool
    public var enableLyrics: Bool
    public var showShuffleAndRepeat: Bool
    public var showMediaOutputControl: Bool
    public var showLiveCanvasInDynamicIsland: Bool
    public var showCpuGraph: Bool
    public var showMemoryGraph: Bool
    public var showGpuGraph: Bool
    public var showNetworkGraph: Bool
    public var showDiskGraph: Bool
    public var timerDisplayMode: String
    public var timerShowsCountdown: Bool
    public var timerShowsLabel: Bool
    public var timerShowsProgress: Bool
    public var timerProgressStyle: String
    public var timerSolidColor: AtollSettingColor
    public var showClipboardIcon: Bool
    public var clipboardDisplayMode: String
    public var clipboardHistorySize: Int
    public var showColorPickerIcon: Bool
    public var colorHistorySize: Int
    public var showColorFormats: Bool
    public var hideCompletedReminders: Bool
    public var showFullEventTitles: Bool
    public var enableReminderLiveActivity: Bool
    public var copyOnDrag: Bool
    public var quickShareProvider: String
    public var showDoNotDisturbLabel: Bool
    public var focusIndicatorNonPersistent: Bool
    public var enableCapsLockIndicator: Bool
    public var showBatteryPercentage: Bool
    public var showPowerStatusIcons: Bool
    public var lowBatteryHUDStyle: String
    public var useCircularBluetoothBatteryIndicator: Bool
    public var showBluetoothBatteryPercentageText: Bool
    public var selectedDownloadIndicatorStyle: String
    public var inlineHUD: Bool
    public var showProgressPercentages: Bool
    public var systemEventIndicatorUseAccent: Bool
    public var enableCustomOSD: Bool
    public var enableVerticalHUD: Bool
    public var enableCircularHUD: Bool
    public var lockScreenWeatherTemperatureUnit: String
    public var lockScreenBatteryShowsBatteryGauge: Bool
    public var extensionLiveActivityCapacity: Int
    public var screenAssistantDisplayMode: String
    public var selectedAIProvider: String

    public init(
        externalDisplayStyle: String,
        enableShadow: Bool,
        cornerRadiusScaling: Bool,
        settingsIconInNotch: Bool,
        showMirror: Bool,
        coloredSpectrogram: Bool,
        playerColorTinting: Bool,
        enableLyrics: Bool,
        showShuffleAndRepeat: Bool,
        showMediaOutputControl: Bool,
        showLiveCanvasInDynamicIsland: Bool,
        showCpuGraph: Bool,
        showMemoryGraph: Bool,
        showGpuGraph: Bool,
        showNetworkGraph: Bool,
        showDiskGraph: Bool,
        timerDisplayMode: String,
        timerShowsCountdown: Bool,
        timerShowsLabel: Bool,
        timerShowsProgress: Bool,
        timerProgressStyle: String,
        timerSolidColor: AtollSettingColor,
        showClipboardIcon: Bool,
        clipboardDisplayMode: String,
        clipboardHistorySize: Int,
        showColorPickerIcon: Bool,
        colorHistorySize: Int,
        showColorFormats: Bool,
        hideCompletedReminders: Bool,
        showFullEventTitles: Bool,
        enableReminderLiveActivity: Bool,
        copyOnDrag: Bool,
        quickShareProvider: String,
        showDoNotDisturbLabel: Bool,
        focusIndicatorNonPersistent: Bool,
        enableCapsLockIndicator: Bool,
        showBatteryPercentage: Bool,
        showPowerStatusIcons: Bool,
        lowBatteryHUDStyle: String,
        useCircularBluetoothBatteryIndicator: Bool,
        showBluetoothBatteryPercentageText: Bool,
        selectedDownloadIndicatorStyle: String,
        inlineHUD: Bool,
        showProgressPercentages: Bool,
        systemEventIndicatorUseAccent: Bool,
        enableCustomOSD: Bool,
        enableVerticalHUD: Bool,
        enableCircularHUD: Bool,
        lockScreenWeatherTemperatureUnit: String,
        lockScreenBatteryShowsBatteryGauge: Bool,
        extensionLiveActivityCapacity: Int,
        screenAssistantDisplayMode: String,
        selectedAIProvider: String
    ) {
        self.externalDisplayStyle = externalDisplayStyle
        self.enableShadow = enableShadow
        self.cornerRadiusScaling = cornerRadiusScaling
        self.settingsIconInNotch = settingsIconInNotch
        self.showMirror = showMirror
        self.coloredSpectrogram = coloredSpectrogram
        self.playerColorTinting = playerColorTinting
        self.enableLyrics = enableLyrics
        self.showShuffleAndRepeat = showShuffleAndRepeat
        self.showMediaOutputControl = showMediaOutputControl
        self.showLiveCanvasInDynamicIsland = showLiveCanvasInDynamicIsland
        self.showCpuGraph = showCpuGraph
        self.showMemoryGraph = showMemoryGraph
        self.showGpuGraph = showGpuGraph
        self.showNetworkGraph = showNetworkGraph
        self.showDiskGraph = showDiskGraph
        self.timerDisplayMode = timerDisplayMode
        self.timerShowsCountdown = timerShowsCountdown
        self.timerShowsLabel = timerShowsLabel
        self.timerShowsProgress = timerShowsProgress
        self.timerProgressStyle = timerProgressStyle
        self.timerSolidColor = timerSolidColor
        self.showClipboardIcon = showClipboardIcon
        self.clipboardDisplayMode = clipboardDisplayMode
        self.clipboardHistorySize = clipboardHistorySize
        self.showColorPickerIcon = showColorPickerIcon
        self.colorHistorySize = colorHistorySize
        self.showColorFormats = showColorFormats
        self.hideCompletedReminders = hideCompletedReminders
        self.showFullEventTitles = showFullEventTitles
        self.enableReminderLiveActivity = enableReminderLiveActivity
        self.copyOnDrag = copyOnDrag
        self.quickShareProvider = quickShareProvider
        self.showDoNotDisturbLabel = showDoNotDisturbLabel
        self.focusIndicatorNonPersistent = focusIndicatorNonPersistent
        self.enableCapsLockIndicator = enableCapsLockIndicator
        self.showBatteryPercentage = showBatteryPercentage
        self.showPowerStatusIcons = showPowerStatusIcons
        self.lowBatteryHUDStyle = lowBatteryHUDStyle
        self.useCircularBluetoothBatteryIndicator = useCircularBluetoothBatteryIndicator
        self.showBluetoothBatteryPercentageText = showBluetoothBatteryPercentageText
        self.selectedDownloadIndicatorStyle = selectedDownloadIndicatorStyle
        self.inlineHUD = inlineHUD
        self.showProgressPercentages = showProgressPercentages
        self.systemEventIndicatorUseAccent = systemEventIndicatorUseAccent
        self.enableCustomOSD = enableCustomOSD
        self.enableVerticalHUD = enableVerticalHUD
        self.enableCircularHUD = enableCircularHUD
        self.lockScreenWeatherTemperatureUnit = lockScreenWeatherTemperatureUnit
        self.lockScreenBatteryShowsBatteryGauge = lockScreenBatteryShowsBatteryGauge
        self.extensionLiveActivityCapacity = extensionLiveActivityCapacity
        self.screenAssistantDisplayMode = screenAssistantDisplayMode
        self.selectedAIProvider = selectedAIProvider
    }

    @MainActor
    public static func current() -> AtollIslandPreviewSettings {
        AtollIslandPreviewSettings(
            externalDisplayStyle: string("island.externalDisplayStyle", fallback: "Dynamic Island"),
            enableShadow: bool("appearance.enableShadow", fallback: true),
            cornerRadiusScaling: bool("appearance.cornerRadiusScaling", fallback: true),
            settingsIconInNotch: bool("appearance.settingsIconInNotch", fallback: true),
            showMirror: bool("appearance.showMirror", fallback: true),
            coloredSpectrogram: bool("appearance.coloredSpectrogram", fallback: true),
            playerColorTinting: bool("appearance.playerColorTinting", fallback: true),
            enableLyrics: bool("media.enableLyrics", fallback: true),
            showShuffleAndRepeat: bool("media.showShuffleAndRepeat", fallback: true),
            showMediaOutputControl: bool("media.showMediaOutputControl", fallback: true),
            showLiveCanvasInDynamicIsland: bool("media.showLiveCanvasInDynamicIsland", fallback: false),
            showCpuGraph: bool("stats.showCpuGraph", fallback: true),
            showMemoryGraph: bool("stats.showMemoryGraph", fallback: true),
            showGpuGraph: bool("stats.showGpuGraph", fallback: true),
            showNetworkGraph: bool("stats.showNetworkGraph", fallback: true),
            showDiskGraph: bool("stats.showDiskGraph", fallback: true),
            timerDisplayMode: string("timer.timerDisplayMode", fallback: "tab"),
            timerShowsCountdown: bool("timer.timerShowsCountdown", fallback: true),
            timerShowsLabel: bool("timer.timerShowsLabel", fallback: true),
            timerShowsProgress: bool("timer.timerShowsProgress", fallback: true),
            timerProgressStyle: string("timer.timerProgressStyle", fallback: "Bar"),
            timerSolidColor: color("timer.timerSolidColor", fallback: .init(red: 0.96, green: 0.52, blue: 0.18)),
            showClipboardIcon: bool("clipboard.showClipboardIcon", fallback: true),
            clipboardDisplayMode: string("clipboard.clipboardDisplayMode", fallback: "separateTab"),
            clipboardHistorySize: int("clipboard.clipboardHistorySize", fallback: 5),
            showColorPickerIcon: bool("colorPicker.showColorPickerIcon", fallback: true),
            colorHistorySize: int("colorPicker.colorHistorySize", fallback: 10),
            showColorFormats: bool("colorPicker.showColorFormats", fallback: true),
            hideCompletedReminders: bool("calendar.hideCompletedReminders", fallback: true),
            showFullEventTitles: bool("calendar.showFullEventTitles", fallback: true),
            enableReminderLiveActivity: bool("calendar.enableReminderLiveActivity", fallback: true),
            copyOnDrag: bool("shelf.copyOnDrag", fallback: true),
            quickShareProvider: string("shelf.quickShareProvider", fallback: "AirDrop"),
            showDoNotDisturbLabel: bool("privacy.showDoNotDisturbLabel", fallback: true),
            focusIndicatorNonPersistent: bool("privacy.focusIndicatorNonPersistent", fallback: false),
            enableCapsLockIndicator: bool("privacy.enableCapsLockIndicator", fallback: true),
            showBatteryPercentage: bool("battery.showBatteryPercentage", fallback: true),
            showPowerStatusIcons: bool("battery.showPowerStatusIcons", fallback: true),
            lowBatteryHUDStyle: string("battery.lowBatteryHUDStyle", fallback: "compact"),
            useCircularBluetoothBatteryIndicator: bool("bluetooth.useCircularBluetoothBatteryIndicator", fallback: false),
            showBluetoothBatteryPercentageText: bool("bluetooth.showBluetoothBatteryPercentageText", fallback: true),
            selectedDownloadIndicatorStyle: string("downloads.selectedDownloadIndicatorStyle", fallback: "Progress"),
            inlineHUD: bool("osd.inlineHUD", fallback: false),
            showProgressPercentages: bool("osd.showProgressPercentages", fallback: true),
            systemEventIndicatorUseAccent: bool("osd.systemEventIndicatorUseAccent", fallback: true),
            enableCustomOSD: bool("osd.enableCustomOSD", fallback: false),
            enableVerticalHUD: bool("osd.enableVerticalHUD", fallback: false),
            enableCircularHUD: bool("osd.enableCircularHUD", fallback: false),
            lockScreenWeatherTemperatureUnit: string("lockScreen.lockScreenWeatherTemperatureUnit", fallback: "Celsius"),
            lockScreenBatteryShowsBatteryGauge: bool("lockScreen.lockScreenBatteryShowsBatteryGauge", fallback: true),
            extensionLiveActivityCapacity: int("extensions.extensionLiveActivityCapacity", fallback: 3),
            screenAssistantDisplayMode: string("screenAssistant.screenAssistantDisplayMode", fallback: "panel"),
            selectedAIProvider: string("screenAssistant.selectedAIProvider", fallback: "openAI")
        )
    }
}

public struct AtollIslandPreviewSampleData: Equatable, Sendable {
    public var media: Media
    public var stats: [Metric]
    public var timer: Timer
    public var clipboard: [String]
    public var colors: [AtollSettingColor]
    public var calendar: [CalendarEvent]
    public var shelfItems: [ShelfItem]

    public init(
        media: Media,
        stats: [Metric],
        timer: Timer,
        clipboard: [String],
        colors: [AtollSettingColor],
        calendar: [CalendarEvent],
        shelfItems: [ShelfItem]
    ) {
        self.media = media
        self.stats = stats
        self.timer = timer
        self.clipboard = clipboard
        self.colors = colors
        self.calendar = calendar
        self.shelfItems = shelfItems
    }

    public static let deterministic = AtollIslandPreviewSampleData(
        media: .init(
            title: "Midnight Build",
            artist: "Atoll Radio",
            lyric: "Keep the lights on",
            progress: 0.58,
            artworkColors: [
                .init(red: 0.98, green: 0.32, blue: 0.42),
                .init(red: 0.99, green: 0.62, blue: 0.20),
                .init(red: 0.44, green: 0.30, blue: 0.96)
            ]
        ),
        stats: [
            .init(id: "cpu", title: "CPU", value: "42%", symbol: "cpu", color: .init(red: 0.21, green: 0.55, blue: 0.98), data: [0.24, 0.32, 0.48, 0.42, 0.56, 0.38, 0.44]),
            .init(id: "memory", title: "Memory", value: "64%", symbol: "memorychip", color: .init(red: 0.20, green: 0.78, blue: 0.36), data: [0.44, 0.48, 0.52, 0.58, 0.63, 0.61, 0.64]),
            .init(id: "gpu", title: "GPU", value: "31%", symbol: "display", color: .init(red: 0.62, green: 0.38, blue: 0.95), data: [0.22, 0.28, 0.25, 0.36, 0.31, 0.29, 0.33]),
            .init(id: "network", title: "Network", value: "1.8M", symbol: "network", color: .init(red: 0.98, green: 0.58, blue: 0.18), data: [0.18, 0.46, 0.24, 0.72, 0.38, 0.64, 0.41]),
            .init(id: "disk", title: "Disk", value: "92K", symbol: "internaldrive", color: .init(red: 0.16, green: 0.78, blue: 0.88), data: [0.12, 0.18, 0.42, 0.22, 0.33, 0.20, 0.27])
        ],
        timer: .init(title: "Focus Sprint", remaining: "06:42", progress: 0.68),
        clipboard: ["git commit --amend", "Notch preview sample", "{\"status\":\"ready\"}"],
        colors: [
            .init(red: 0.96, green: 0.20, blue: 0.30),
            .init(red: 0.98, green: 0.58, blue: 0.18),
            .init(red: 0.98, green: 0.84, blue: 0.22),
            .init(red: 0.24, green: 0.74, blue: 0.42),
            .init(red: 0.22, green: 0.55, blue: 0.98),
            .init(red: 0.56, green: 0.36, blue: 0.94)
        ],
        calendar: [
            .init(id: "review", title: "Design review", time: "10:30"),
            .init(id: "focus", title: "Focus block", time: "13:00"),
            .init(id: "ship", title: "Release notes", time: "16:15")
        ],
        shelfItems: [
            .init(id: "draft", title: "Draft.md", symbol: "doc.text.fill"),
            .init(id: "shot", title: "Preview.png", symbol: "photo.fill"),
            .init(id: "bundle", title: "Assets", symbol: "folder.fill")
        ]
    )

    public struct Media: Equatable, Sendable {
        public var title: String
        public var artist: String
        public var lyric: String
        public var progress: Double
        public var artworkColors: [AtollSettingColor]

        public init(title: String, artist: String, lyric: String, progress: Double, artworkColors: [AtollSettingColor]) {
            self.title = title
            self.artist = artist
            self.lyric = lyric
            self.progress = progress
            self.artworkColors = artworkColors
        }
    }

    public struct Metric: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var value: String
        public var symbol: String
        public var color: AtollSettingColor
        public var data: [Double]

        public init(id: String, title: String, value: String, symbol: String, color: AtollSettingColor, data: [Double]) {
            self.id = id
            self.title = title
            self.value = value
            self.symbol = symbol
            self.color = color
            self.data = data
        }
    }

    public struct Timer: Equatable, Sendable {
        public var title: String
        public var remaining: String
        public var progress: Double

        public init(title: String, remaining: String, progress: Double) {
            self.title = title
            self.remaining = remaining
            self.progress = progress
        }
    }

    public struct CalendarEvent: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var time: String

        public init(id: String, title: String, time: String) {
            self.id = id
            self.title = title
            self.time = time
        }
    }

    public struct ShelfItem: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var symbol: String

        public init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }
}

private extension AtollIslandPreviewSettings {
    @MainActor
    static func bool(_ id: String, fallback: Bool) -> Bool {
        guard case .bool(let value) = AtollSettingsBridge.value(for: id) else { return fallback }
        return value
    }

    @MainActor
    static func int(_ id: String, fallback: Int) -> Int {
        switch AtollSettingsBridge.value(for: id) {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value.rounded())
        case .string(let value):
            return Int(value) ?? fallback
        default:
            return fallback
        }
    }

    @MainActor
    static func double(_ id: String, fallback: Double) -> Double {
        switch AtollSettingsBridge.value(for: id) {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let value):
            return Double(value) ?? fallback
        default:
            return fallback
        }
    }

    @MainActor
    static func string(_ id: String, fallback: String) -> String {
        switch AtollSettingsBridge.value(for: id) {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(Int(value.rounded()))
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return fallback
        }
    }

    @MainActor
    static func color(_ id: String, fallback: AtollSettingColor) -> AtollSettingColor {
        guard case .color(let value) = AtollSettingsBridge.value(for: id) else { return fallback }
        return value
    }
}
