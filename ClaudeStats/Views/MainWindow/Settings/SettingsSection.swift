import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case features
    case menuBar
    case notchIsland
    case platforms
    case tracking
    case leaderboards
    case github
    case systemMonitor
    case terminal
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   "General"
        case .features:  "Features"
        case .menuBar:   "Menu Bar"
        case .notchIsland: "Notch Island"
        case .platforms: "Platforms"
        case .tracking:  "Tracking"
        case .leaderboards: "Leaderboards"
        case .github:    "GitHub"
        case .systemMonitor: "System Monitor"
        case .terminal:  "Terminal"
        case .about:     "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:   "gearshape"
        case .features:  "switch.2"
        case .menuBar:   "menubar.rectangle"
        case .notchIsland: "capsule.portrait.tophalf.filled"
        case .platforms: "square.stack.3d.up"
        case .tracking:  "waveform.path.ecg"
        case .leaderboards: "trophy"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .systemMonitor: "cpu"
        case .terminal:  "terminal"
        case .about:     "info.circle"
        }
    }
}
