import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private static let refreshOptions = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Startup") {
                VStack(spacing: 0) {
                    SettingRow(title: "Launch at login",
                               description: "Open Claude Stats automatically when you log in to your Mac.") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.setEnabled(newValue) }
                }
                .settingCard()
            }

            SettingGroup(title: "Refresh") {
                VStack(spacing: 0) {
                    SettingRow(title: "Refresh every",
                               description: "How often Claude Stats re-scans your session logs in the background.") {
                        Picker("", selection: $prefs.autoRefreshMinutes) {
                            ForEach(Self.refreshOptions, id: \.self) { minutes in
                                Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }
                    .onChange(of: prefs.autoRefreshMinutes) { _, _ in env.applyAutoRefreshSetting() }
                }
                .settingCard()
            }

            SettingGroup(title: "Behavior") {
                VStack(spacing: 0) {
                    SettingRow(title: "Remember selected platform",
                               description: "When off, the app starts on the first enabled platform each launch instead of the one you last viewed.") {
                        Toggle("", isOn: $prefs.rememberSelectedProvider)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Include cache reads in token counts",
                               description: "Anthropic's API re-reports the cached context on every assistant turn, so the same tokens get counted many times. Turn off to show only \u{201C}new\u{201D} traffic (input + output + cache writes). Estimated cost is unaffected.") {
                        Toggle("", isOn: $prefs.includeCacheInTokens)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .settingCard()
            }
        }
    }
}

#if DEBUG
#Preview {
    GeneralSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
