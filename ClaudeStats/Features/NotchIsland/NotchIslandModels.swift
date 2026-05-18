import Foundation

enum NotchIslandDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case primaryDisplay
    case pointerDisplay
    case allDisplays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primaryDisplay: "Primary Display"
        case .pointerDisplay: "Pointer Display"
        case .allDisplays: "All Displays"
        }
    }

    var description: String {
        switch self {
        case .primaryDisplay: "Pin the island to the main screen."
        case .pointerDisplay: "Move the island to the screen under the pointer."
        case .allDisplays: "Show a separate island on every connected display."
        }
    }
}

enum NotchIslandSizePreset: String, CaseIterable, Sendable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var description: String {
        switch self {
        case .compact: "Small top pill with a focused expanded panel."
        case .regular: "Balanced size for media, stats, and utilities."
        case .large: "More room for lists, shelf items, and lock-screen widgets."
        }
    }
}

enum NotchIslandModule: String, CaseIterable, Sendable, Identifiable {
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
    case terminal

    static let defaultEnabled: Set<NotchIslandModule> = [.stats, .battery, .privacy]

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .stats: "cpu"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard"
        case .colorPicker: "eyedropper"
        case .calendar: "calendar"
        case .shelf: "tray.and.arrow.down"
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
        case .terminal: "terminal"
        }
    }

    var settingsDescription: String {
        switch self {
        case .media: "Atoll media controls, artwork, and playback live activity."
        case .stats: "CPU, memory, disk, network, battery, GPU, and thermal readouts."
        case .timer: "Inline timer controls and timer live activity."
        case .clipboard: "Clipboard history surface and popover entry point."
        case .colorPicker: "Color picker entry point and picked-colour feedback."
        case .calendar: "Calendar and reminder previews near the notch."
        case .shelf: "File shelf, AirDrop, QuickShare, and LocalSend surfaces."
        case .privacy: "Camera and microphone privacy indicators."
        case .recording: "Screen-recording live activity and indicator."
        case .focus: "Do Not Disturb and Focus live activity."
        case .battery: "Battery, charging, and power-source live activity."
        case .bluetooth: "Bluetooth audio device status and connection HUD."
        case .downloads: "Browser download live activity and progress display."
        case .osd: "Volume, brightness, keyboard backlight, and custom HUD overlays."
        case .lockScreenWidgets: "Atoll-style lock-screen panels and widgets."
        case .extensionBridge: "Atoll extension RPC/XPC event bridge."
        case .screenAssistant: "Screen assistant panels, screenshot snipping, and model chooser."
        case .terminal: "Terminal tab surface backed by the existing embedded terminal stack."
        }
    }

    var isHeavyOrExperimental: Bool {
        switch self {
        case .media, .stats, .timer, .clipboard, .colorPicker, .calendar, .privacy, .battery:
            false
        case .shelf, .recording, .focus, .bluetooth, .downloads, .osd, .lockScreenWidgets, .extensionBridge, .screenAssistant, .terminal:
            true
        }
    }

    var atollSourceHint: String {
        switch self {
        case .media: "ThirdParty/Atoll/DynamicIsland/MediaControllers"
        case .stats: "ThirdParty/Atoll/DynamicIsland/components/Stats"
        case .timer: "ThirdParty/Atoll/DynamicIsland/components/Timer"
        case .clipboard: "ThirdParty/Atoll/DynamicIsland/components/Clipboard"
        case .colorPicker: "ThirdParty/Atoll/DynamicIsland/components/ColorPicker"
        case .calendar: "ThirdParty/Atoll/DynamicIsland/components/Calendar"
        case .shelf: "ThirdParty/Atoll/DynamicIsland/components/Shelf"
        case .privacy: "ThirdParty/Atoll/DynamicIsland/components/Privacy"
        case .recording: "ThirdParty/Atoll/DynamicIsland/components/Recording"
        case .focus: "ThirdParty/Atoll/DynamicIsland/components/Focus"
        case .battery: "ThirdParty/Atoll/DynamicIsland/components/Live activities/DynamicIslandBattery.swift"
        case .bluetooth: "ThirdParty/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift"
        case .downloads: "ThirdParty/Atoll/DynamicIsland/components/Downloads"
        case .osd: "ThirdParty/Atoll/DynamicIsland/components/OSD"
        case .lockScreenWidgets: "ThirdParty/Atoll/DynamicIsland/components/LockScreen"
        case .extensionBridge: "ThirdParty/Atoll/DynamicIsland/services/Extensions"
        case .screenAssistant: "ThirdParty/Atoll/DynamicIsland/components/ScreenAssistant"
        case .terminal: "ThirdParty/Atoll/DynamicIsland/managers/TerminalManager.swift"
        }
    }
}

enum NotchIslandPermissionState: Sendable, Equatable {
    case available
    case needsPermission(String)
    case disabledByDefault
    case sourceLinked

    var displayName: String {
        switch self {
        case .available: "Available"
        case .needsPermission(let permission): "Needs \(permission)"
        case .disabledByDefault: "Off by default"
        case .sourceLinked: "Source linked"
        }
    }
}
