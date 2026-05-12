import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var fullDiskAccessOK = ScreenTimeService.canRead()
    @State private var newIDEBundleID = ""

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

            aiActivitySection(prefs: prefs)

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

    @ViewBuilder
    private func aiActivitySection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        Section("AI activity analysis") {
            Toggle("Enable AI activity analysis", isOn: $prefs.aiActivityAnalysisEnabled)
            Text("Adds an Activity tab that compares your editor's focus time (from macOS Screen Time) with Claude Code activity. Reading Screen Time requires Full Disk Access.")
                .font(.sora(11))
                .foregroundStyle(.secondary)

            if prefs.aiActivityAnalysisEnabled {
                LabeledContent("Full Disk Access") {
                    HStack(spacing: 8) {
                        Text(fullDiskAccessOK ? "Granted" : "Not granted")
                            .foregroundStyle(fullDiskAccessOK ? .secondary : Color.stxAccent)
                        if !fullDiskAccessOK {
                            Button("Open Settings…") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        Button("Re-check") { fullDiskAccessOK = ScreenTimeService.canRead() }
                    }
                }

                DisclosureGroup("Editors counted as \u{201C}editor time\u{201D}") {
                    ForEach(IDEAppCatalog.defaults) { app in
                        Toggle(app.name, isOn: Binding(
                            get: { !prefs.ideBundleIDsRemoved.contains(app.bundleID) },
                            set: { included in
                                if included {
                                    prefs.ideBundleIDsRemoved.removeAll { $0 == app.bundleID }
                                } else if !prefs.ideBundleIDsRemoved.contains(app.bundleID) {
                                    prefs.ideBundleIDsRemoved.append(app.bundleID)
                                }
                            }))
                    }
                    ForEach(prefs.ideBundleIDsAdded, id: \.self) { id in
                        HStack {
                            Text(id).foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove") { prefs.ideBundleIDsAdded.removeAll { $0 == id } }
                        }
                    }
                    HStack {
                        TextField("Add bundle id (e.g. com.example.editor)", text: $newIDEBundleID)
                        Button("Add") {
                            let id = newIDEBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !id.isEmpty,
                                  !prefs.ideBundleIDsAdded.contains(id),
                                  !IDEAppCatalog.defaults.contains(where: { $0.bundleID == id }) else { return }
                            prefs.ideBundleIDsAdded.append(id)
                            newIDEBundleID = ""
                        }
                        .disabled(newIDEBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
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
