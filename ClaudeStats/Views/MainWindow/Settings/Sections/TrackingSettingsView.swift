import SwiftUI

struct TrackingSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onSelectSection: (SettingsSection) -> Void = { _ in }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            gitTrackingGroup(prefs: prefs)
        }
    }

    @ViewBuilder
    private func gitTrackingGroup(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        SettingGroup(
            title: "Git Tracking",
            caption: "Reads commit history from repositories opened or used by configured AI coding tools via the `git` command."
        ) {
            if !prefs.gitTrackingEnabled {
                FeatureDisabledNotice(
                    featureName: "Git Tracking",
                    message: "Turn it on in Features to edit git workspace behavior."
                ) {
                    onSelectSection(.features)
                }
            }

            repositorySourcesCard(prefs: prefs)
                .disabledSettingsBlock(!prefs.gitTrackingEnabled)

            VStack(spacing: 0) {
                SettingRow(title: "Open git view in") {
                    Picker("", selection: $prefs.gitOpensInWindow) {
                        Text("Panel tab").tag(false)
                        Text("Separate window").tag(true)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                SettingRowDivider()
                SettingRow(
                    title: "Diff block granularity",
                    description: "Fine separates mixed changes into modified, inserted, and deleted bands; Coarse keeps each change region as one block."
                ) {
                    Picker("", selection: $prefs.gitDiffBlockGranularity) {
                        ForEach(GitDiffBlockGranularity.allCases) { granularity in
                            Text(granularity.displayName).tag(granularity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                }
                SettingRowDivider()
                SettingRow(
                    title: "Language engine",
                    description: "Language detection uses GitHub Linguist; scc supplies line counts."
                ) {
                    Text("GitHub Linguist + scc")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }
                SettingRowDivider()
                SettingRow(
                    title: "Statistics scope",
                    description: "HEAD counts committed code; Working Tree includes local uncommitted files."
                ) {
                    Picker("", selection: $prefs.gitStatsScope) {
                        ForEach(GitStatsScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 220)
                }
            }
            .settingCard()
            .disabledSettingsBlock(!prefs.gitTrackingEnabled)
        }
    }

    private func repositorySourcesCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Repository sources")
                    .font(.sora(13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: "Session sources",
                caption: "Transcript working directories.",
                sources: GitWorkspaceSourceCatalog.sessionSources,
                prefs: prefs
            )

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: "AI editor workspace history",
                caption: "Workspace folders remembered by each editor.",
                sources: GitWorkspaceSourceCatalog.editorSources,
                prefs: prefs
            )
        }
        .settingCard()
    }

    private func gitWorkspaceSourceSection(
        title: String,
        caption: String,
        sources: [GitWorkspaceSourceDescriptor],
        prefs: Preferences
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            let rows = Array(sources.enumerated())
            ForEach(rows, id: \.element.id) { index, source in
                if index > 0 { SettingRowDivider() }
                gitWorkspaceSourceRow(source, prefs: prefs)
            }
        }
    }

    private func gitWorkspaceSourceRow(_ source: GitWorkspaceSourceDescriptor, prefs: Preferences) -> some View {
        let isOn = prefs.gitWorkspaceSourceIDs.contains(source.id)
        let isLastEnabled = isOn && prefs.gitWorkspaceSourceIDs.count == 1
        return HStack(spacing: 12) {
            Image(source.assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .opacity(isOn ? 1 : 0.45)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.sora(13, weight: .medium))
                Text(source.detail)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { prefs.gitWorkspaceSourceIDs.contains(source.id) },
                set: { enabled in
                    var ids = prefs.gitWorkspaceSourceIDs
                    if enabled {
                        ids.insert(source.id)
                    } else {
                        ids.remove(source.id)
                    }
                    prefs.gitWorkspaceSourceIDs = ids
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isLastEnabled)
            .help(isLastEnabled ? "At least one repository source must stay enabled." : source.detail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
