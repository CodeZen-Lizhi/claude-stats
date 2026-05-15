import SwiftUI

/// Top-level container for "settings mode": pairs the dedicated
/// `SettingsSidebarColumn` with a `DetailPanel` rendering the selected
/// `SettingsSection`. Owned (and toggled on/off) by ``MainWindowView``.
struct SettingsModeView: View {
    var onExit: () -> Void

    @SceneStorage("mainWindow.settingsSection") private var sectionRaw: String = SettingsSection.general.rawValue
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarColumn(section: $section, onExit: onExit)
                .frame(width: 220)

            DetailPanel(roundedLeading: true) {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        Text(section.title)
                            .font(.sora(28, weight: .semibold))
                            .padding(.bottom, 4)
                        sectionContent
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                }
            }
        }
        .onAppear { section = SettingsSection(rawValue: sectionRaw) ?? .general }
        .onChange(of: section) { _, new in sectionRaw = new.rawValue }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .general:   GeneralSettingsView()
        case .menuBar:   MenuBarSettingsView()
        case .platforms: PlatformsSettingsView()
        case .tracking:  TrackingSettingsView()
        case .leaderboards: LeaderboardsSettingsView()
        case .github:    GitHubSettingsView()
        case .about:     AboutSettingsView()
        }
    }
}

#if DEBUG
#Preview("Settings mode") {
    SettingsModeView(onExit: {})
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(VisualEffectBackground())
}
#endif
