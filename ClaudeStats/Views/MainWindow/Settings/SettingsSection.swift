import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case menuBar
    case platforms
    case tracking
    case github
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   "General"
        case .menuBar:   "Menu Bar"
        case .platforms: "Platforms"
        case .tracking:  "Tracking"
        case .github:    "GitHub"
        case .about:     "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:   "gearshape"
        case .menuBar:   "menubar.rectangle"
        case .platforms: "square.stack.3d.up"
        case .tracking:  "waveform.path.ecg"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .about:     "info.circle"
        }
    }
}
