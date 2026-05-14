import SwiftUI
import AppKit

struct TrackingSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var fullDiskAccessOK = ScreenTimeService.canRead()
    @State private var newIDEBundleID = ""

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            aiActivityGroup(prefs: prefs)
            gitTrackingGroup(prefs: prefs)
        }
    }

    // MARK: - AI activity

    @ViewBuilder
    private func aiActivityGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(
            title: "AI Activity Analysis",
            caption: "Adds an Activity tab that compares your editor's focus time (from macOS Screen Time) with Claude Code activity. Reading Screen Time requires Full Disk Access."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Enable AI activity analysis") {
                    Toggle("", isOn: $prefs.aiActivityAnalysisEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if prefs.aiActivityAnalysisEnabled {
                    SettingRowDivider()
                    fullDiskAccessRow
                }
            }
            .settingCard()

            if prefs.aiActivityAnalysisEnabled {
                ideListCard(prefs: prefs)
            }
        }
    }

    private var fullDiskAccessRow: some View {
        SettingRow(title: "Full Disk Access",
                   description: "Required so Claude Stats can read the local Screen Time database.") {
            HStack(spacing: 8) {
                Text(fullDiskAccessOK ? "Granted" : "Not granted")
                    .font(.sora(12))
                    .foregroundStyle(fullDiskAccessOK ? Color.stxMuted : Color.stxAccent)
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
    }

    @ViewBuilder
    private func ideListCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Editors counted as \u{201C}editor time\u{201D}")
                    .font(.sora(13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            SettingRowDivider()

            ForEach(IDEAppCatalog.defaults) { app in
                let binding = Binding(
                    get: { !prefs.ideBundleIDsRemoved.contains(app.bundleID) },
                    set: { included in
                        if included {
                            prefs.ideBundleIDsRemoved.removeAll { $0 == app.bundleID }
                        } else if !prefs.ideBundleIDsRemoved.contains(app.bundleID) {
                            prefs.ideBundleIDsRemoved.append(app.bundleID)
                        }
                    }
                )
                ideRow(name: app.name, subtitle: app.bundleID, isOn: binding)
                SettingRowDivider()
            }

            ForEach(prefs.ideBundleIDsAdded, id: \.self) { id in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(id).font(.sora(13, weight: .medium))
                        Text("Custom").font(.sora(11)).foregroundStyle(Color.stxMuted)
                    }
                    Spacer()
                    Button("Remove") { prefs.ideBundleIDsAdded.removeAll { $0 == id } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                SettingRowDivider()
            }

            HStack(spacing: 8) {
                TextField("Add bundle id (e.g. com.example.editor)", text: $newIDEBundleID)
                    .textFieldStyle(.roundedBorder)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .settingCard()
    }

    private func ideRow(name: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.sora(13, weight: .medium))
                Text(subtitle).font(.sora(11)).foregroundStyle(Color.stxMuted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Git tracking

    @ViewBuilder
    private func gitTrackingGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(
            title: "Git Tracking",
            caption: "Reads commit history of repos you've used Claude Code in (via the `git` command) and compares it with your Claude activity — churn, recent commits, and a usage-vs-commits timeline."
        ) {
            VStack(spacing: 0) {
                SettingRow(title: "Enable git tracking") {
                    Toggle("", isOn: $prefs.gitTrackingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if prefs.gitTrackingEnabled {
                    SettingRowDivider()
                    SettingRow(title: "Open git view in") {
                        Picker("", selection: $prefs.gitOpensInWindow) {
                            Text("Panel tab").tag(false)
                            Text("Separate window").tag(true)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }
            }
            .settingCard()
        }
    }
}

#if DEBUG
#Preview {
    TrackingSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
