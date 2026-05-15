import SwiftUI

struct LeaderboardsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var canSync: Bool {
        env.preferences.leaderboardsEnabled
            && !env.preferences.leaderboardNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && env.leaderboards.syncStatus != .syncing
            && env.leaderboards.syncStatus != .checkingAccount
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "CloudKit Leaderboards",
                caption: "Publishes aggregate scores to CloudKit's public database. The app never uploads prompts, paths, session titles, model names, or transcript content."
            ) {
                VStack(spacing: 0) {
                    SettingRow(title: "Join leaderboards",
                               description: "Disabled by default. Turning this on uses your iCloud account only to write aggregate scores.") {
                        Toggle("", isOn: $prefs.leaderboardsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if prefs.leaderboardsEnabled {
                        SettingRowDivider()
                        nicknameRow(prefs: prefs)
                        SettingRowDivider()
                        statusRow
                        SettingRowDivider()
                        syncRow
                    }
                }
                .settingCard()
            }

            if prefs.leaderboardsEnabled {
                activityNote
                privacyGroup
            }
        }
        .task { await env.leaderboards.checkAccountStatus() }
        .onChange(of: prefs.leaderboardsEnabled) { _, enabled in
            if enabled {
                Task { await env.leaderboards.syncIfDue(force: false) }
            }
        }
    }

    private func nicknameRow(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return SettingRow(title: "Public nickname",
                          description: "Shown on the leaderboard instead of your iCloud identity.") {
            TextField("Nickname", text: $prefs.leaderboardNickname)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { Task { await env.leaderboards.syncNow() } }
        }
    }

    private var statusRow: some View {
        SettingRow(title: "Status") {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    if env.leaderboards.syncStatus == .checkingAccount || env.leaderboards.syncStatus == .syncing {
                        ProgressView().controlSize(.mini)
                    }
                    Text(env.leaderboards.syncStatus.displayText)
                        .font(.sora(12))
                        .foregroundStyle(statusColor)
                }
                Text(env.leaderboards.accountState.displayText)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var syncRow: some View {
        SettingRow(title: "Sync",
                   description: "Runs once per day while the app is open. You can force a sync here.") {
            HStack(spacing: 8) {
                if let last = env.preferences.leaderboardLastSyncedAt {
                    Text(Format.shortDate(last))
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Button("Sync now") {
                    Task { await env.leaderboards.syncNow() }
                }
                .disabled(!canSync)
            }
        }
    }

    private var activityNote: some View {
        let canSubmitActivity = env.preferences.aiActivityAnalysisEnabled && ScreenTimeService.canRead()
        return SettingGroup(title: "Activity Score") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: canSubmitActivity ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(canSubmitActivity ? Color.stxMuted : Color.stxAccent)
                Text(canSubmitActivity
                     ? "Activity minutes will be included in leaderboard syncs."
                     : "Activity minutes are skipped until AI Activity Analysis is enabled and Full Disk Access is granted.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            .settingCard()
        }
    }

    private var privacyGroup: some View {
        SettingGroup(title: "Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                privacyLine("Uploaded: nickname, metric, UTC period, aggregate score, app version, update time.")
                privacyLine("Never uploaded: prompts, transcript text, project paths, filenames, model names, costs, or session titles.")
                privacyLine("Leaderboard periods use UTC so everyone competes in the same day/week/month window.")
            }
            .settingCard()
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Color.stxAccent)
            Text(text)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        switch env.leaderboards.syncStatus {
        case .failed, .needsNickname:
            return .stxAccent
        default:
            return .stxMuted
        }
    }
}

#if DEBUG
#Preview {
    LeaderboardsSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
