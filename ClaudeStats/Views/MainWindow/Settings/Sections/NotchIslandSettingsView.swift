import SwiftUI

struct NotchIslandSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onSelectSection: (SettingsSection) -> Void = { _ in }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            if !prefs.notchIslandEnabled {
                FeatureDisabledNotice(
                    featureName: "Notch Island",
                    message: "Turn it on in Features to edit display behavior and modules."
                ) {
                    onSelectSection(.features)
                }
            }

            SettingGroup(title: "Display") {
                VStack(spacing: 0) {
                    SettingRow(title: "Display mode",
                               description: "Where the island window is created.") {
                        Picker("", selection: $prefs.notchIslandDisplayMode) {
                            ForEach(NotchIslandDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 190)
                    }

                    SettingRowDivider()

                    SettingRow(title: "Size",
                               description: "Compact and expanded island dimensions.") {
                        Picker("", selection: $prefs.notchIslandSizePreset) {
                            ForEach(NotchIslandSizePreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }

                    SettingRowDivider()

                    SettingRow(title: "Hover expansion",
                               description: "Expand while the pointer is over the island.") {
                        Toggle("", isOn: $prefs.notchIslandHoverExpansionEnabled)
                            .labelsHidden()
                    }

                    SettingRowDivider()

                    SettingRow(title: "Shortcut bridge",
                               description: "Toggle the island with Command-Option-N.") {
                        Toggle("", isOn: $prefs.notchIslandShortcutEnabled)
                            .labelsHidden()
                    }
                }
                .settingCard()
            }
            .disabledSettingsBlock(!prefs.notchIslandEnabled)

            SettingGroup(title: "Modules", caption: "Heavy or permissioned Atoll modules stay off unless you enable them here.") {
                VStack(spacing: 0) {
                    ForEach(NotchIslandModule.allCases) { module in
                        moduleRow(module, prefs: prefs)
                        if module.id != NotchIslandModule.allCases.last?.id {
                            SettingRowDivider()
                        }
                    }
                }
                .settingCard()
            }
            .disabledSettingsBlock(!prefs.notchIslandEnabled)
        }
    }

    private func moduleRow(_ module: NotchIslandModule, prefs: Preferences) -> some View {
        let descriptor = NotchIslandFeatureRegistry.descriptor(for: module)
        return SettingRow(
            title: module.title,
            description: module.settingsDescription
        ) {
            HStack(spacing: 10) {
                Text(descriptor.permissionState.displayName)
                    .font(.sora(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(module.isHeavyOrExperimental ? Color.stxMuted : Color.primary)
                Toggle("", isOn: moduleBinding(module, prefs: prefs))
                    .labelsHidden()
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
    }

    private func moduleBinding(_ module: NotchIslandModule, prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.notchIslandEnabledModules.contains(module) },
            set: { isEnabled in
                var modules = prefs.notchIslandEnabledModules
                if isEnabled {
                    modules.insert(module)
                } else {
                    modules.remove(module)
                }
                prefs.notchIslandEnabledModules = modules
            }
        )
    }
}

#if DEBUG
#Preview("Notch Island Settings") {
    NotchIslandSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 780)
}
#endif
