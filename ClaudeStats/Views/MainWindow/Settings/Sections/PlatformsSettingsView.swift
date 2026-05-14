import SwiftUI

struct PlatformsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(
                title: "AI Coding Tools",
                caption: "Pick which platforms to track. Enable more than one and a platform switcher appears at the top of the panel."
            ) {
                VStack(spacing: 0) {
                    let kinds = Array(ProviderKind.allCases.enumerated())
                    ForEach(kinds, id: \.element) { (index, kind) in
                        if index > 0 { SettingRowDivider() }
                        platformRow(kind: kind, prefs: prefs)
                    }
                }
                .settingCard()
            }
        }
    }

    private func platformRow(kind: ProviderKind, prefs: Preferences) -> some View {
        let binding = Binding(
            get: { prefs.enabledProviders.contains(kind) },
            set: { on in
                if on {
                    prefs.enabledProviders.insert(kind)
                } else if prefs.enabledProviders.count > 1 {
                    prefs.enabledProviders.remove(kind)
                }
            }
        )
        let isLastEnabled = prefs.enabledProviders.count == 1 && prefs.enabledProviders.contains(kind)
        return HStack(alignment: .center, spacing: 16) {
            Image(kind.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.sora(13, weight: .medium))
                if isLastEnabled {
                    Text("At least one platform must stay enabled.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isLastEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#if DEBUG
#Preview {
    PlatformsSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
