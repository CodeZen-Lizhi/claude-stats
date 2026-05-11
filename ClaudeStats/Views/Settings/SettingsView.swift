import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private static let refreshOptions = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var prefs = env.preferences
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.setEnabled(newValue) }

                Picker("Refresh every", selection: $prefs.autoRefreshMinutes) {
                    ForEach(Self.refreshOptions, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .onChange(of: prefs.autoRefreshMinutes) { _, _ in env.applyAutoRefreshSetting() }
            }

            Section("Menu bar") {
                Picker("Show", selection: $prefs.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("For", selection: $prefs.menuBarPeriod) {
                    ForEach(StatsPeriod.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Data") {
                LabeledContent("Claude config directory") {
                    Text(ClaudePaths.default.configDirectory.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ClaudePaths.default.configDirectory])
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersionString)
            }
        }
        .formStyle(.grouped)
        .font(.sora(12))
        .frame(width: 440)
        .navigationTitle("Claude Stats Settings")
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
#endif
