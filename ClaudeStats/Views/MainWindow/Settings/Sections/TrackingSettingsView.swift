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
            title: L10n.string("settings.tracking.title", defaultValue: "仓库来源"),
            caption: L10n.string("settings.tracking.caption", defaultValue: "本地读取 Codex 使用过的 Git 仓库；编辑器来源只做匹配补充，不上传代码。")
        ) {
            if !prefs.gitTrackingEnabled {
                FeatureDisabledNotice(
                    featureName: L10n.string("settings.tracking.feature_name", defaultValue: "仓库来源"),
                    message: L10n.string("settings.tracking.disabled", defaultValue: "请先在「功能」里开启 Git 跟踪。")
                ) {
                    onSelectSection(.features)
                }
            }

            repositorySourcesCard(prefs: prefs)
                .disabledSettingsBlock(!prefs.gitTrackingEnabled)
        }
    }

    private func repositorySourcesCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("settings.tracking.sources.title", defaultValue: "仓库来源"))
                    .font(.sora(13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: L10n.string("settings.tracking.sources.session_title", defaultValue: "Codex 会话"),
                caption: L10n.string("settings.tracking.sources.session_caption", defaultValue: "从 session cwd 归并到 Git root。"),
                sources: GitWorkspaceSourceCatalog.sessionSources,
                prefs: prefs
            )

            SettingRowDivider()

            gitWorkspaceSourceSection(
                title: L10n.string("settings.tracking.sources.editor_title", defaultValue: "编辑器辅助来源"),
                caption: L10n.string("settings.tracking.sources.editor_caption", defaultValue: "只用于匹配/补全标签，不单独加入未使用 Codex 的项目。"),
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
        let isRequired = source.id == .codex
        let isLastEnabled = isOn && prefs.gitWorkspaceSourceIDs.count == 1
        return HStack(spacing: 12) {
            sourceIcon(source, isOn: isOn)
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
                    if isRequired { return }
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
            .disabled(isRequired || isLastEnabled)
            .help(sourceHelp(source, isRequired: isRequired, isLastEnabled: isLastEnabled))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sourceIcon(_ source: GitWorkspaceSourceDescriptor, isOn: Bool) -> some View {
        if source.assetName.isEmpty {
            Image(systemName: "hammer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.primary : Color.stxMuted.opacity(0.65))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(source.assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .opacity(isOn ? 1 : 0.45)
                .accessibilityHidden(true)
        }
    }

    private func sourceHelp(_ source: GitWorkspaceSourceDescriptor, isRequired: Bool, isLastEnabled: Bool) -> String {
        if isRequired {
            return L10n.string("settings.tracking.sources.required", defaultValue: "Codex 是主来源，不能关闭。")
        }
        if isLastEnabled {
            return L10n.string("git.sources.minimum_one", defaultValue: "至少保留一个仓库来源。")
        }
        return source.detail
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
