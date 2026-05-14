import SwiftUI

struct GitHubSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tokenDraft: String = ""
    @State private var githubError: String?

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "GitHub Comparison",
                caption: "Adds a GitHub contributions heatmap to the Dashboard plus an Overlap view that classifies each day as Both / Local-only / GitHub-only / Neither. Reads only your contribution counts via the GitHub GraphQL API — no code, issues, or PR data."
            ) {
                VStack(spacing: 0) {
                    SettingRow(title: "Enable GitHub comparison") {
                        Toggle("", isOn: $prefs.githubEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .settingCard()
            }

            if prefs.githubEnabled {
                connectionGroup(prefs: prefs)
                appearanceGroup(prefs: prefs)
            }
        }
    }

    @ViewBuilder
    private func connectionGroup(prefs: Preferences) -> some View {
        SettingGroup(title: "Connection") {
            VStack(spacing: 0) {
                statusRow
                SettingRowDivider()
                connectionControls(prefs: prefs)
            }
            .settingCard()
        }
    }

    private var statusRow: some View {
        SettingRow(title: "Status") {
            Group {
                switch env.github.status {
                case .disconnected:
                    Text("Not connected").foregroundStyle(Color.stxMuted)
                case .connecting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Connecting…").foregroundStyle(Color.stxMuted)
                    }
                case .connected(let login, let syncedAt, let isStale):
                    HStack(spacing: 6) {
                        Text("@\(login)")
                        if let syncedAt {
                            Text("· UPD \(Format.relativeDate(syncedAt))")
                                .foregroundStyle(Color.stxMuted)
                        }
                        if isStale {
                            Text("(stale)").foregroundStyle(Color.stxAccent)
                        }
                    }
                case .failed(let reason):
                    Text(reason).foregroundStyle(Color.stxAccent)
                }
            }
            .font(.sora(12))
        }
    }

    @ViewBuilder
    private func connectionControls(prefs: Preferences) -> some View {
        switch env.github.status {
        case .disconnected, .failed:
            tokenInput
        case .connecting:
            HStack {
                ProgressView().controlSize(.mini)
                Text("Connecting…").font(.sora(11)).foregroundStyle(Color.stxMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        case .connected:
            HStack(spacing: 8) {
                Button("Sync now") { Task { await env.github.syncNow() } }
                Button("Disconnect", role: .destructive) {
                    env.github.disconnect(login: env.preferences.githubLogin)
                    env.preferences.githubLogin = ""
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var tokenInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("Personal access token", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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

    private func saveGitHubToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        githubError = nil
        Task {
            do {
                let login = try await env.github.connect(token: token)
                env.preferences.githubLogin = login
                tokenDraft = ""
            } catch let err as GitHubClient.ClientError {
                githubError = String(describing: err)
            } catch {
                githubError = error.localizedDescription
            }
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
