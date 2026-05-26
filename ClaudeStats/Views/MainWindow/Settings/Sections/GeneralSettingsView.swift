import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var languageRestartNoticeVisible = false

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
                    SettingRowDivider()
                    SettingRow(title: "Open main window on launch",
                               description: "Show the main window when Claude Stats starts, including when you double-click the app.") {
                        Toggle("", isOn: $prefs.openMainWindowOnLaunch)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Language") {
                VStack(spacing: 0) {
                    SettingRow(title: "App language",
                               description: "Choose the language Claude Stats uses after the next restart.") {
                        Picker("", selection: $prefs.appLanguagePreference) {
                            ForEach(AppLanguagePreference.allCases) { language in
                                Text(language.displayName()).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 170)
                    }
                    .onChange(of: prefs.appLanguagePreference) { _, _ in
                        languageRestartNoticeVisible = true
                    }
                    if languageRestartNoticeVisible {
                        SettingRowDivider()
                        Text(L10n.restartLanguageNotice())
                            .font(.sora(11))
                            .foregroundStyle(Color.stxAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Refresh") {
                VStack(spacing: 0) {
                    SettingRow(title: "Refresh every",
                               description: "How often Claude Stats re-scans your session logs in the background.") {
                        Picker("", selection: $prefs.autoRefreshMinutes) {
                            ForEach(Self.refreshOptions, id: \.self) { minutes in
                                Text(L10n.refreshInterval(minutes: minutes)).tag(minutes)
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
                    SettingRow(title: "Detail edge fade",
                               description: "Blend the main detail pane into the sidebar with a soft boundary fade.") {
                        Toggle("", isOn: $prefs.detailPanelBoundaryFalloffEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Include cache reads in token counts",
                               description: "Some APIs re-report cached context on assistant turns, so the same tokens can be counted many times. Turn off to show only \u{201C}new\u{201D} traffic (input + output + cache writes). Estimated cost is unaffected.") {
                        Toggle("", isOn: $prefs.includeCacheInTokens)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    SettingRowDivider()
                    SettingRow(title: "Cost mode",
                               description: "API estimate uses standard first-party token prices. Detailed billing is kept for compatible imported data and currently matches the standard Codex estimate.") {
                        Picker("", selection: $prefs.costEstimationMode) {
                            ForEach(CostEstimationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 170)
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
