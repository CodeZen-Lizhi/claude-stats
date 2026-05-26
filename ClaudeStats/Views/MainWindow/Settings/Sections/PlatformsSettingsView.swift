import AppKit
import SwiftUI

struct PlatformsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldEnableClaudeStatusAlertsAfterSettings = false
    @State private var shouldEnableOpenAIStatusAlertsAfterSettings = false

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

            claudeUsageLimitsGroup(prefs: prefs)
            claudeStatusGroup(prefs: prefs)
            openAIStatusGroup(prefs: prefs)
        }
        .task {
            await loadStatusSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await refreshNotificationAuthorizationAfterActivation()
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
                .toggleStyle(.appSwitch)
                .disabled(isLastEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func claudeUsageLimitsGroup(prefs: Preferences) -> some View {
        SettingGroup(
            title: "Claude Usage Limits",
            caption: "5h and 7d limits are always shown. Extra Claude Desktop plan rows can be shown when the GUI capture finds them."
        ) {
            VStack(spacing: 0) {
                claudeDesktopAutoCaptureRow(prefs: prefs)
                SettingRowDivider()
                claudeDesktopTimedCaptureRow(prefs: prefs)
                let optionalRows = Array(UsageLimitWindowCatalog.claudeOptionalWindowIDs.enumerated())
                ForEach(optionalRows, id: \.element) { _, windowID in
                    SettingRowDivider()
                    claudeUsageLimitWindowRow(windowID, prefs: prefs)
                }
            }
            .settingCard()
        }
    }

    private func claudeDesktopAutoCaptureRow(prefs: Preferences) -> some View {
        SettingRow(
            title: "Claude Desktop auto capture",
            description: "Choose whether Claude Stats reads visible Claude Desktop usage limits automatically."
        ) {
            Picker(
                L10n.string("usage.limit.desktop_auto.picker", defaultValue: "Claude Desktop auto capture"),
                selection: Binding(
                    get: { prefs.claudeDesktopUsageAutoMode },
                    set: { prefs.claudeDesktopUsageAutoMode = $0 }
                )
            ) {
                ForEach(ClaudeDesktopUsageAutoMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 210)
        }
    }

    private func claudeDesktopTimedCaptureRow(prefs: Preferences) -> some View {
        SettingRow(
            title: "Timed capture",
            description: "Periodically reads Claude Desktop usage while Claude usage is selected."
        ) {
            Toggle("", isOn: Binding(
                get: { prefs.claudeDesktopUsageTimedCaptureEnabled },
                set: { prefs.claudeDesktopUsageTimedCaptureEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
        }
    }

    private func claudeUsageLimitWindowRow(_ windowID: String, prefs: Preferences) -> some View {
        let metadata = UsageLimitWindowCatalog.claudeMetadata(for: windowID)
        return SettingRow(
            title: metadata?.label ?? windowID,
            description: "Show this extra Claude Desktop usage window in the Usage Limits panel."
        ) {
            Toggle("", isOn: Binding(
                get: { prefs.claudeUsageLimitVisibleWindowIDs.contains(windowID) },
                set: { isVisible in
                    var ids = prefs.claudeUsageLimitVisibleWindowIDs
                    if isVisible {
                        ids.insert(windowID)
                    } else {
                        ids.remove(windowID)
                    }
                    prefs.claudeUsageLimitVisibleWindowIDs = ids
                }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
        }
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
                    claudeStatusAlertsControl(prefs: prefs)
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

    private func claudeStatusAlertsControl(prefs: Preferences) -> some View {
        HStack(spacing: 8) {
            if env.claudeStatus.notificationPermissionDenied {
                Button("Open Settings...") {
                    shouldEnableClaudeStatusAlertsAfterSettings = true
                    openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("", isOn: Binding(
                get: { prefs.claudeStatusNotificationsEnabled },
                set: { enabled in setClaudeStatusAlertsEnabled(enabled) }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
            .disabled(env.claudeStatus.isRequestingNotificationAuthorization)
            .help(env.claudeStatus.notificationPermissionDenied
                ? L10n.string("platforms.notifications.help.open_settings",
                              defaultValue: "Open macOS Notifications settings to allow alerts.")
                : L10n.string("platforms.claude_status.help.enable_alerts",
                              defaultValue: "Enable Claude Status alerts."))
        }
    }

    private var claudeStatusAlertsDescription: String {
        if env.claudeStatus.isRequestingNotificationAuthorization {
            return L10n.string("platforms.notifications.waiting_permission",
                               defaultValue: "Waiting for macOS notification permission.")
        }
        if env.claudeStatus.notificationPermissionDenied {
            return L10n.string("platforms.notifications.permission_denied",
                               defaultValue: "Notification permission is denied in macOS Settings. Open Settings to allow alerts.")
        }
        return L10n.string("platforms.claude_status.alerts_description",
                           defaultValue: "Send a macOS notification when any shown Claude component is not operational.")
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
            .toggleStyle(.appSwitch)
            .disabled(isVisible && !canHide)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func openAIStatusGroup(prefs: Preferences) -> some View {
        SettingGroup(
            title: "OpenAI Status",
            caption: "Shows selected OpenAI product health on the Dashboard. Alerts only monitor the product groups shown here."
        ) {
            VStack(spacing: 0) {
                SettingRow(
                    title: "Status alerts",
                    description: openAIStatusAlertsDescription
                ) {
                    openAIStatusAlertsControl(prefs: prefs)
                }
                SettingRowDivider()
                let groups = Array(env.openAIStatus.availableGroups.enumerated())
                ForEach(groups, id: \.element.id) { index, group in
                    if index > 0 { SettingRowDivider() }
                    openAIStatusGroupRow(group)
                }
            }
            .settingCard()
        }
    }

    private func openAIStatusAlertsControl(prefs: Preferences) -> some View {
        HStack(spacing: 8) {
            if env.openAIStatus.notificationPermissionDenied {
                Button("Open Settings...") {
                    shouldEnableOpenAIStatusAlertsAfterSettings = true
                    openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("", isOn: Binding(
                get: { prefs.openAIStatusNotificationsEnabled },
                set: { enabled in setOpenAIStatusAlertsEnabled(enabled) }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
            .disabled(env.openAIStatus.isRequestingNotificationAuthorization)
            .help(env.openAIStatus.notificationPermissionDenied
                ? L10n.string("platforms.notifications.help.open_settings",
                              defaultValue: "Open macOS Notifications settings to allow alerts.")
                : L10n.string("platforms.openai_status.help.enable_alerts",
                              defaultValue: "Enable OpenAI Status alerts."))
        }
    }

    private var openAIStatusAlertsDescription: String {
        if env.openAIStatus.isRequestingNotificationAuthorization {
            return L10n.string("platforms.notifications.waiting_permission",
                               defaultValue: "Waiting for macOS notification permission.")
        }
        if env.openAIStatus.notificationPermissionDenied {
            return L10n.string("platforms.notifications.permission_denied",
                               defaultValue: "Notification permission is denied in macOS Settings. Open Settings to allow alerts.")
        }
        return L10n.string("platforms.openai_status.alerts_description",
                           defaultValue: "Send a macOS notification when any shown OpenAI product group is not operational.")
    }

    private func openAIStatusGroupRow(_ group: OpenAIStatusGroup) -> some View {
        let isVisible = env.openAIStatus.isGroupVisible(group)
        let canHide = env.openAIStatus.canHideGroup(group)
        return HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(group.status.settingsTint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.sora(13, weight: .medium))
                Text(group.status.displayName)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { env.openAIStatus.isGroupVisible(group) },
                set: { env.openAIStatus.setGroupVisibility(group, isVisible: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.appSwitch)
            .disabled(isVisible && !canHide)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func loadStatusSettings() async {
        await env.claudeStatus.refreshNotificationAuthorizationStatus()
        await env.claudeStatus.refreshIfNeeded()
        await env.openAIStatus.refreshNotificationAuthorizationStatus()
        await env.openAIStatus.refreshIfNeeded()
    }

    private func setClaudeStatusAlertsEnabled(_ enabled: Bool) {
        if !enabled {
            shouldEnableClaudeStatusAlertsAfterSettings = false
            Task { @MainActor in
                await env.claudeStatus.setNotificationsEnabled(false)
            }
            return
        }

        shouldEnableClaudeStatusAlertsAfterSettings = true
        Task { @MainActor in
            await env.claudeStatus.refreshNotificationAuthorizationStatus()

            if env.claudeStatus.notificationPermissionDenied {
                openNotificationSettings()
                return
            }

            await env.claudeStatus.setNotificationsEnabled(true)
            if env.claudeStatus.notificationAuthorization.canSendNotifications {
                shouldEnableClaudeStatusAlertsAfterSettings = false
            }
        }
    }

    private func setOpenAIStatusAlertsEnabled(_ enabled: Bool) {
        if !enabled {
            shouldEnableOpenAIStatusAlertsAfterSettings = false
            Task { @MainActor in
                await env.openAIStatus.setNotificationsEnabled(false)
            }
            return
        }

        shouldEnableOpenAIStatusAlertsAfterSettings = true
        Task { @MainActor in
            await env.openAIStatus.refreshNotificationAuthorizationStatus()

            if env.openAIStatus.notificationPermissionDenied {
                openNotificationSettings()
                return
            }

            await env.openAIStatus.setNotificationsEnabled(true)
            if env.openAIStatus.notificationAuthorization.canSendNotifications {
                shouldEnableOpenAIStatusAlertsAfterSettings = false
            }
        }
    }

    private func refreshNotificationAuthorizationAfterActivation() async {
        await env.claudeStatus.refreshNotificationAuthorizationStatus()
        await env.openAIStatus.refreshNotificationAuthorizationStatus()

        if shouldEnableClaudeStatusAlertsAfterSettings,
           env.claudeStatus.notificationAuthorization.canSendNotifications {
            await env.claudeStatus.setNotificationsEnabled(true)
            shouldEnableClaudeStatusAlertsAfterSettings = false
        }

        if shouldEnableOpenAIStatusAlertsAfterSettings,
           env.openAIStatus.notificationAuthorization.canSendNotifications {
            await env.openAIStatus.setNotificationsEnabled(true)
            shouldEnableOpenAIStatusAlertsAfterSettings = false
        }
    }

    private func openNotificationSettings() {
        var candidateStrings: [String] = []
        if let bundleID = Bundle.main.bundleIdentifier {
            candidateStrings.append("x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)")
        }
        candidateStrings.append("x-apple.systempreferences:com.apple.preference.notifications")
        candidateStrings.append("x-apple.systempreferences:com.apple.Notifications-Settings.extension")

        for candidate in candidateStrings {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
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

private extension OpenAIStatusSeverity {
    var settingsTint: Color {
        switch self {
        case .operational: Color.green
        case .underMaintenance: Color.blue
        case .degradedPerformance: Color.orange
        case .partialOutage, .fullOutage: Color.red
        case .unknown: Color.stxMuted
        }
    }
}
