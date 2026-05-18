import SwiftUI

struct GitHubSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onSelectSection: (SettingsSection) -> Void = { _ in }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            if !prefs.githubEnabled {
                FeatureDisabledNotice(
                    featureName: "GitHub Comparison",
                    message: "Turn it on in Features to connect a GitHub account and edit comparison settings."
                ) {
                    onSelectSection(.features)
                }
            }

            VStack(alignment: .leading, spacing: 28) {
                connectionGroup
                appearanceGroup(prefs: prefs)
            }
            .disabledSettingsBlock(!prefs.githubEnabled)
        }
    }

    @ViewBuilder
    private var connectionGroup: some View {
        SettingGroup(
            title: "Connection",
            caption: "Adds a GitHub contributions heatmap to the Dashboard plus an Overlap view. Reads contribution counts only."
        ) {
            GitHubConnectionSettings()
                .settingCard()
        }
    }

    @ViewBuilder
    private func appearanceGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(title: "Appearance") {
            VStack(spacing: 0) {
                SettingRow(title: "Overlap palette",
                           description: "Colour scheme used by the Overlap heatmap on the Dashboard.") {
                    Picker("", selection: $prefs.overlapPalette) {
                        ForEach(OverlapPalette.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
            }
            .settingCard()
        }
    }
}

#if DEBUG
#Preview {
    GitHubSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
