import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Show", caption: "Pick which metric the menu-bar status item displays.") {
                SettingSegmentCard(
                    selection: $prefs.menuBarMetric,
                    options: [
                        .init(value: .tokens,
                              title: "Tokens",
                              subtitle: "Total tokens across the chosen period.",
                              symbol: "number"),
                        .init(value: .cost,
                              title: "Cost",
                              subtitle: "Estimated USD across the chosen period.",
                              symbol: "dollarsign.circle"),
                    ]
                )
            }

            SettingGroup(title: "Period") {
                VStack(spacing: 0) {
                    SettingRow(title: "Time range",
                               description: "How far back to add up the menu-bar metric.") {
                        Picker("", selection: $prefs.menuBarPeriod) {
                            ForEach(StatsPeriod.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }

                    if prefs.menuBarMetric == .tokens {
                        SettingRowDivider()
                        SettingRow(title: "Include cache reads",
                                   description: "Independent from the in-app setting, so the menu bar can show a less inflated figure (or vice versa).") {
                            Toggle("", isOn: $prefs.menuBarIncludesCache)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Backup entry", caption: "Keep Claude Stats reachable when the macOS menu bar is crowded.") {
                SettingRow(title: "Floating edge tab",
                           description: "Shows a small screen-edge tab that expands into a mini summary on hover. Drag it to snap to any edge.") {
                    Toggle("", isOn: $prefs.floatingTabEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .settingCard()
            }
        }
    }
}

#if DEBUG
#Preview {
    MenuBarSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
