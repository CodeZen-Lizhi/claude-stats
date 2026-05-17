import SwiftUI

struct SystemMonitorSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Preview") {
                SystemMonitorPreview()
            }

            SettingGroup(title: "Availability") {
                VStack(spacing: 0) {
                    SettingRow(
                        title: "Enable System Monitor",
                        description: "Shows the System page in Tools and starts read-only sampling only while that page is open."
                    ) {
                        Toggle("", isOn: $prefs.systemMonitorEnabled)
                            .labelsHidden()
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Refresh Rate", caption: "Lower rates reduce energy impact.") {
                SystemMonitorRefreshRatePicker(selection: $prefs.systemMonitorRefreshRate)
            }

            SettingGroup(title: "Modules") {
                VStack(spacing: 0) {
                    ForEach(SystemMonitorModule.allCases) { module in
                        SettingRow(title: module.title, description: module.settingsDescription) {
                            Toggle("", isOn: moduleBinding(module, prefs: prefs))
                                .labelsHidden()
                        }
                        if module.id != SystemMonitorModule.allCases.last?.id {
                            SettingRowDivider()
                        }
                    }
                }
                .settingCard()
            }
        }
    }

    private func moduleBinding(_ module: SystemMonitorModule, prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.systemMonitorVisibleModules.contains(module) },
            set: { isVisible in
                var modules = prefs.systemMonitorVisibleModules
                if isVisible {
                    modules.insert(module)
                } else {
                    modules.remove(module)
                }
                prefs.systemMonitorVisibleModules = modules
            }
        )
    }
}

private struct SystemMonitorRefreshRatePicker: View {
    @Binding var selection: SystemMonitorRefreshRate

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { options }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) { options }
        }
    }

    @ViewBuilder
    private var options: some View {
        ForEach(SystemMonitorRefreshRate.allCases) { rate in
            Button {
                selection = rate
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rate.displayName)
                        .font(.sora(13, weight: .semibold).monospacedDigit())
                    Text(rate.description)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selection == rate ? Color.stxAccent : Color.stxStroke,
                                      lineWidth: selection == rate ? 1.5 : 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("System Monitor Settings") {
    SystemMonitorSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 760)
}
#endif
