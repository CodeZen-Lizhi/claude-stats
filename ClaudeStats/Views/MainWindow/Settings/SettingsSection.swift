import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case features
    case menuBar
    case notchIsland
    case tracking
    case dictionary
    case localAI
    case leaderboards
    case github
    case linuxDo
    case systemMonitor
    case terminal
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   L10n.string("settings.section.general", defaultValue: "General")
        case .features:  L10n.string("settings.section.features", defaultValue: "Features")
        case .menuBar:   L10n.string("settings.section.menu_bar", defaultValue: "Menu Bar")
        case .notchIsland: L10n.string("settings.section.notch_island", defaultValue: "Notch Island")
        case .tracking:  L10n.string("settings.section.tracking", defaultValue: "Tracking")
        case .dictionary: "Dictionary"
        case .localAI: "Local AI"
        case .leaderboards: L10n.string("settings.section.leaderboards", defaultValue: "Leaderboards")
        case .github:    "GitHub"
        case .linuxDo:   "LinuxDo"
        case .systemMonitor: L10n.string("settings.section.system_monitor", defaultValue: "System Monitor")
        case .terminal:  L10n.string("settings.section.terminal", defaultValue: "Terminal")
        case .about:     L10n.string("settings.section.about", defaultValue: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general:   "gearshape"
        case .features:  "switch.2"
        case .menuBar:   "menubar.rectangle"
        case .notchIsland: "capsule.portrait.tophalf.filled"
        case .tracking:  "waveform.path.ecg"
        case .dictionary: "text.book.closed"
        case .localAI: "brain"
        case .leaderboards: "trophy"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .linuxDo:   "globe.asia.australia"
        case .systemMonitor: "cpu"
        case .terminal:  "terminal"
        case .about:     "info.circle"
        }
    }

    var assetName: String? {
        switch self {
        case .linuxDo: "LinuxDoLogo"
        default: nil
        }
    }
}
