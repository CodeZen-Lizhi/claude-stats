import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case features
    case menuBar
    case pricing
    case tracking
    case github
    case systemMonitor
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   L10n.string("settings.section.general", defaultValue: "General")
        case .features:  L10n.string("settings.section.features", defaultValue: "Features")
        case .menuBar:   L10n.string("settings.section.menu_bar", defaultValue: "Menu Bar")
        case .pricing:   L10n.string("settings.section.pricing", defaultValue: "Model Pricing")
        case .tracking:  L10n.string("settings.section.tracking", defaultValue: "Repository Sources")
        case .github:    "GitHub"
        case .systemMonitor: L10n.string("settings.section.system_monitor", defaultValue: "System Monitor")
        case .about:     L10n.string("settings.section.about", defaultValue: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general:   "gearshape"
        case .features:  "switch.2"
        case .menuBar:   "menubar.rectangle"
        case .pricing:   "dollarsign.circle"
        case .tracking:  "folder.badge.gearshape"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .systemMonitor: "cpu"
        case .about:     "info.circle"
        }
    }
}
