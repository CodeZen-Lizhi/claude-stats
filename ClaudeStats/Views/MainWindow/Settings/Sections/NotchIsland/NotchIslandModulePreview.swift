import AtollEmbed
import SwiftUI

struct NotchIslandModulePreview: View {
    let tab: NotchIslandSettingsTab
    let preferences: Preferences
    let refreshToken: Int

    var body: some View {
        let _ = refreshToken

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview")
                    .font(.sora(13, weight: .semibold))
                Spacer()
                Text(previewStatus)
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            AtollIslandPreviewView(configuration: previewConfiguration)
                .frame(maxWidth: .infinity, minHeight: 252, maxHeight: 252)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.stxStroke, lineWidth: 1)
                        }
                }
        }
    }

    private var previewStatus: String {
        if !preferences.notchIslandEnabled {
            return "Disabled"
        }
        if let module = tab.module {
            return preferences.notchIslandEnabledModules.contains(module) ? "Enabled" : "Off"
        }
        return preferences.notchIslandSizePreset.displayName
    }

    private var previewConfiguration: AtollIslandPreviewConfiguration {
        AtollIslandPreviewConfiguration(
            selectedTab: tab.previewTab,
            enabledTabs: Set(preferences.notchIslandEnabledModules.map(\.previewTab)),
            sizePreset: preferences.notchIslandSizePreset.previewSizePreset,
            isFeatureEnabled: preferences.notchIslandEnabled,
            hoverExpansionEnabled: preferences.notchIslandHoverExpansionEnabled,
            settings: AtollIslandPreviewSettings.current()
        )
    }
}

extension NotchIslandSettingsTab {
    var previewTab: AtollIslandPreviewTab {
        if let module {
            return module.previewTab
        }

        switch self {
        case .island:
            return .island
        case .appearance:
            return .appearance
        default:
            return .island
        }
    }
}

extension NotchIslandModule {
    var previewTab: AtollIslandPreviewTab {
        switch self {
        case .media:
            return .media
        case .stats:
            return .stats
        case .timer:
            return .timer
        case .clipboard:
            return .clipboard
        case .colorPicker:
            return .colorPicker
        case .calendar:
            return .calendar
        case .shelf:
            return .shelf
        case .privacy:
            return .privacy
        case .recording:
            return .recording
        case .focus:
            return .focus
        case .battery:
            return .battery
        case .bluetooth:
            return .bluetooth
        case .downloads:
            return .downloads
        case .osd:
            return .osd
        case .lockScreenWidgets:
            return .lockScreenWidgets
        case .extensionBridge:
            return .extensionBridge
        case .screenAssistant:
            return .screenAssistant
        }
    }
}

extension NotchIslandSizePreset {
    var previewSizePreset: AtollIslandPreviewSizePreset {
        switch self {
        case .compact:
            return .compact
        case .regular:
            return .regular
        case .large:
            return .large
        }
    }
}
