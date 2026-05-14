import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var fullDiskAccessOK = ScreenTimeService.canRead()
    @State private var newIDEBundleID = ""
    @State private var tokenDraft: String = ""
    @State private var githubError: String?

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

                Toggle("Remember selected platform", isOn: $prefs.rememberSelectedProvider)
                Text("When off, the app starts on the first enabled platform each launch instead of the one you last viewed.")
                    .font(.sora(11))
                    .foregroundStyle(.secondary)

                Toggle("Include cache reads in token counts", isOn: $prefs.includeCacheInTokens)
                Text("Anthropic's API re-reports the cached context on every assistant turn, so the same tokens get counted many times. Turn this off to show only \u{201C}new\u{201D} traffic (input + output + cache writes). Estimated cost is always calculated per-category and is unaffected.")
                    .font(.sora(11))
                    .foregroundStyle(.secondary)
            }

            platformsSection(prefs: prefs)

            Section("Menu bar") {
                Picker("Show", selection: $prefs.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("For", selection: $prefs.menuBarPeriod) {
                    ForEach(StatsPeriod.allCases) { Text($0.displayName).tag($0) }
                }
                if prefs.menuBarMetric == .tokens {
                    Toggle("Include cache reads", isOn: $prefs.menuBarIncludesCache)
                }
            }

            aiActivitySection(prefs: prefs)

            gitTrackingSection(prefs: prefs)

            githubSection(prefs: prefs)

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
                Button("Check for Updates…") { env.updater.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        .font(.sora(12))
        .frame(width: 440)
        .navigationTitle("Claude Stats Settings")
    }

    @ViewBuilder
    private func platformsSection(prefs: Preferences) -> some View {
        Section("Platforms") {
            Text("Pick the AI coding tools to track. Enable more than one and a platform switcher appears at the top of the panel.")
                .font(.sora(11))
                .foregroundStyle(.secondary)
            ForEach(ProviderKind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { prefs.enabledProviders.contains(kind) },
                    set: { on in
                        if on {
                            prefs.enabledProviders.insert(kind)
                        } else if prefs.enabledProviders.count > 1 {
                            prefs.enabledProviders.remove(kind)
                        }
                    })) {
                    Label {
                        Text(kind.displayName)
                    } icon: {
                        Image(kind.assetName).resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                }
                .disabled(prefs.enabledProviders.count == 1 && prefs.enabledProviders.contains(kind))
            }
        }
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

    @ViewBuilder
    private func gitTrackingSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        Section("Git tracking") {
            Toggle("Enable git tracking", isOn: $prefs.gitTrackingEnabled)
            Text("Reads the commit history of the repositories you've used Claude Code in (via the `git` command) and compares it with your Claude activity — churn, recent commits, and a usage-vs-commits timeline.")
                .font(.sora(11))
                .foregroundStyle(.secondary)

            if prefs.gitTrackingEnabled {
                Picker("Open git view in", selection: $prefs.gitOpensInWindow) {
                    Text("Panel tab").tag(false)
                    Text("Separate window").tag(true)
                }
            }
        }
    }

    @ViewBuilder
    private func githubSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        Section("GitHub") {
            Toggle("Enable GitHub comparison", isOn: $prefs.githubEnabled)
            Text("Adds a GitHub contributions heatmap to the Dashboard plus an Overlap view that classifies each day as Both / Local-only / GitHub-only / Neither. Reads only your contribution counts via the GitHub GraphQL API — no code, issues, or PR data.")
                .font(.sora(11))
                .foregroundStyle(.secondary)

            if prefs.githubEnabled {
                githubStatusRow

                switch env.dashboard.githubStatus {
                case .disconnected, .failed:
                    githubTokenInput
                case .connecting:
                    HStack { ProgressView().controlSize(.mini); Text("Connecting…").font(.sora(11)) }
                case .connected:
                    githubConnectedControls
                }

                Picker("Overlap palette", selection: $prefs.overlapPalette) {
                    ForEach(OverlapPalette.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var githubStatusRow: some View {
        LabeledContent("Status") {
            switch env.dashboard.githubStatus {
            case .disconnected:
                Text("Not connected").foregroundStyle(.secondary)
            case .connecting:
                ProgressView().controlSize(.mini)
            case .connected(let login, let syncedAt, let isStale):
                HStack(spacing: 6) {
                    Text("@\(login)")
                    if let syncedAt {
                        Text("· UPD \(Format.relativeDate(syncedAt))")
                            .foregroundStyle(.secondary)
                    }
                    if isStale {
                        Text("(stale)").foregroundStyle(Color.stxAccent)
                    }
                }
            case .failed(let reason):
                Text(reason).foregroundStyle(Color.stxAccent)
            }
        }
    }

    private var githubTokenInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField("Personal access token", text: $tokenDraft)
                Button("Save") { saveGitHubToken() }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let githubError {
                Text(githubError)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxAccent)
            }
            Link("Create a fine-grained token (no scopes needed)…",
                 destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                .font(.sora(11))
        }
    }

    private var githubConnectedControls: some View {
        HStack {
            Button("Sync now") { Task { await env.dashboard.syncGitHubNow() } }
            Button("Disconnect", role: .destructive) {
                env.dashboard.disconnectGitHub(login: env.preferences.githubLogin)
                env.preferences.githubLogin = ""
            }
        }
    }

    private func saveGitHubToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        githubError = nil
        Task {
            do {
                let login = try await env.dashboard.connectGitHub(token: token)
                env.preferences.githubLogin = login
                tokenDraft = ""
            } catch let err as GitHubClient.ClientError {
                githubError = String(describing: err)
            } catch {
                githubError = error.localizedDescription
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
