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

            claudeStatusGroup(prefs: prefs)
        }
        .task {
            await env.claudeStatus.refreshNotificationAuthorizationStatus()
            await env.claudeStatus.refreshIfNeeded()
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

    private func claudeStatusGroup(prefs: Preferences) -> some View {
        SettingGroup(
            title: "Claude Status",
            caption: "Shows selected Claude service health on the Dashboard. Alerts only monitor the components shown here."
        ) {
            VStack(spacing: 0) {
                SettingRow(
                    title: "Status alerts",
                    description: claudeStatusAlertsDescription
                ) {
                    Toggle("", isOn: Binding(
                        get: { prefs.claudeStatusNotificationsEnabled },
                        set: { enabled in
                            Task { await env.claudeStatus.setNotificationsEnabled(enabled) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(env.claudeStatus.isRequestingNotificationAuthorization)
                }
                SettingRowDivider()
                let components = Array(env.claudeStatus.availableComponents.enumerated())
                ForEach(components, id: \.element.id) { index, component in
                    if index > 0 { SettingRowDivider() }
                    claudeStatusComponentRow(component)
                }
            }
            .settingCard()
        }
    }

    private var claudeStatusAlertsDescription: String {
        if env.claudeStatus.isRequestingNotificationAuthorization {
            return "Waiting for macOS notification permission."
        }
        if env.claudeStatus.notificationPermissionDenied {
            return "Notification permission is denied in macOS Settings."
        }
        return "Send a macOS notification when any shown Claude component is not operational."
    }

    private func claudeStatusComponentRow(_ component: ClaudeStatusComponent) -> some View {
        let isVisible = env.claudeStatus.isComponentVisible(component)
        let canHide = env.claudeStatus.canHideComponent(component)
        return HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(component.status.settingsTint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                    .font(.sora(13, weight: .medium))
                Text(component.status.displayName)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { env.claudeStatus.isComponentVisible(component) },
                set: { env.claudeStatus.setComponentVisibility(component, isVisible: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isVisible && !canHide)
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

private extension ClaudeStatusSeverity {
    var settingsTint: Color {
        switch self {
        case .operational: Color.green
        case .underMaintenance: Color.blue
        case .degradedPerformance: Color.orange
        case .partialOutage, .majorOutage: Color.red
        case .unknown: Color.stxMuted
        }
    }
}
