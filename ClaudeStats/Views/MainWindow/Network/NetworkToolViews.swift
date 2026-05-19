import AppKit
import SwiftUI

struct NetworkProxyView: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            localProxyCard
            systemProxyCard
            NetworkHelperView(store: store)
            NetworkUpstreamView(store: store)
            commandsCard
        }
        .task {
            store.refreshPassiveHelperStatus()
        }
        .alert(item: $store.upstreamProxyConfirmation) { confirmation in
            Alert(
                title: Text("Chain Existing System Proxy?"),
                message: Text("Route Rockxy through \(confirmation.summary) before enabling the system proxy."),
                primaryButton: .default(Text("Chain")) {
                    store.confirmUpstreamProxyChaining()
                },
                secondaryButton: .cancel {
                    store.cancelUpstreamProxyChaining()
                }
            )
        }
    }

    private var localProxyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Local Proxy", systemImage: "network")
                    .font(.sora(14, weight: .semibold))
                NetworkStatusBadge(
                    text: store.statusMessage,
                    symbol: store.captureStatus.isListening ? "dot.radiowaves.left.and.right" : "circle",
                    tint: store.captureStatus.isListening ? .green : Color.stxMuted
                )
                Spacer()
            }

            NetworkInfoGrid(items: [
                NetworkInfoItem(title: "Listen", value: endpoint, symbol: "point.3.connected.trianglepath.dotted"),
                NetworkInfoItem(title: "Captured", value: "\(store.flows.count)", symbol: "list.bullet.rectangle"),
                NetworkInfoItem(title: "Visible", value: "\(store.filteredFlows.count)", symbol: "line.3.horizontal.decrease.circle"),
                NetworkInfoItem(title: "Selected", value: store.selectedFlow?.domainDisplay ?? "None", symbol: "scope"),
            ])

            HStack(spacing: 10) {
                Button {
                    store.startCapture()
                } label: {
                    Label("Start Capture", systemImage: "play.fill")
                }
                .disabled(store.captureStatus.isListening)

                Button {
                    store.stopCapture()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!store.captureStatus.isListening)

                Button {
                    store.clearFlows()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(store.flows.isEmpty)

                Spacer()
            }
            .font(.sora(11, weight: .medium))
        }
        .mainWindowPanel()
    }

    private var systemProxyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("System Proxy", systemImage: "switch.2")
                    .font(.sora(14, weight: .semibold))
                NetworkStatusBadge(
                    text: store.systemProxyStatus.isEnabled ? "Enabled" : "Idle",
                    symbol: store.systemProxyStatus.isEnabled ? "checkmark.circle.fill" : "circle",
                    tint: store.systemProxyStatus.isEnabled ? .green : Color.stxMuted
                )
                Spacer()
            }

            HStack(alignment: .center, spacing: 12) {
                Toggle(isOn: $store.autoEnableSystemProxyOnStart) {
                    Label("Auto-enable on start", systemImage: "bolt.horizontal")
                        .font(.sora(11, weight: .medium))
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button {
                    store.enableSystemProxy()
                } label: {
                    Label("Enable", systemImage: "switch.2")
                }
                .disabled(!store.captureStatus.isListening || store.systemProxyStatus.isEnabled || store.isSystemProxyWorking)

                Button {
                    store.disableSystemProxy()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.systemProxyStatus.isEnabled || store.isSystemProxyWorking)
            }
            .font(.sora(11, weight: .medium))

            NetworkInfoGrid(items: [
                NetworkInfoItem(title: "Managed", value: managedServicesText, symbol: "network"),
                NetworkInfoItem(title: "Upstream", value: store.systemProxyStatus.upstreamProxySummary ?? "Direct", symbol: "arrow.triangle.branch"),
                NetworkInfoItem(title: "Restore Scope", value: store.systemProxyStatus.isEnabled ? "This session" : "None", symbol: "arrow.uturn.backward.circle"),
            ])

            if let error = store.systemProxyStatus.lastError, !error.isEmpty {
                NetworkInlineMessage(text: error, tint: .red, symbol: "exclamationmark.triangle")
            }
        }
        .mainWindowPanel()
    }

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Manual Setup", systemImage: "terminal")
                .font(.sora(14, weight: .semibold))

            Text("Use these commands when system proxy cannot be changed automatically.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)

            VStack(alignment: .leading, spacing: 8) {
                command("export HTTP_PROXY=http://\(endpoint)")
                command("export HTTPS_PROXY=http://\(endpoint)")
                command("curl -x http://\(endpoint) http://httpbin.org/get")
            }
        }
        .mainWindowPanel()
    }

    private var endpoint: String {
        store.listeningEndpoint?.displayName ?? "127.0.0.1:9090"
    }

    private var managedServicesText: String {
        store.systemProxyStatus.managedServices.isEmpty
            ? "None"
            : store.systemProxyStatus.managedServices.joined(separator: ", ")
    }

    private func command(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct NetworkUpstreamView: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Upstream Proxy", systemImage: "arrow.triangle.branch")
                    .font(.sora(14, weight: .semibold))
                NetworkStatusBadge(
                    text: upstreamBadgeText,
                    symbol: upstreamBadgeSymbol,
                    tint: upstreamBadgeTint
                )

                Spacer()

                Picker("", selection: $store.upstreamProxyMode) {
                    ForEach(NetworkUpstreamProxyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            NetworkInfoGrid(items: [
                NetworkInfoItem(title: "Mode", value: store.upstreamProxyMode.title, symbol: "point.3.connected.trianglepath.dotted"),
                NetworkInfoItem(title: "Route", value: routeSummary, symbol: "arrow.triangle.branch"),
                NetworkInfoItem(title: "Localhost", value: localhostBypassText, symbol: "location.slash"),
                NetworkInfoItem(title: "SOCKS DNS", value: socksDNSText, symbol: "network.badge.shield.half.filled"),
            ])

            modeControls

            if store.upstreamProxyMode == .manual {
                StxRule()
                manualUpstreamProxyFields
            }

            StxRule()

            routeScopeFields

            HStack(spacing: 10) {
                Spacer()

                Button {
                    store.applyCurrentUpstreamProxy()
                } label: {
                    Label("Apply Route", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isUpstreamProxyWorking)

                Button {
                    store.testUpstreamProxy()
                } label: {
                    Label("Test", systemImage: "checkmark.circle")
                }
                .disabled(store.isUpstreamProxyWorking)
            }
            .font(.sora(11, weight: .medium))

            if let message = store.upstreamProxyStatusMessage, !message.isEmpty {
                NetworkInlineMessage(
                    text: message,
                    tint: store.upstreamProxyTestResult?.isReachable == false ? .red : Color.stxMuted,
                    symbol: store.upstreamProxyTestResult?.isReachable == false ? "exclamationmark.triangle" : "info.circle"
                )
            }
        }
        .mainWindowPanel()
    }

    @ViewBuilder
    private var modeControls: some View {
        switch store.upstreamProxyMode {
        case .automatic:
            Toggle(isOn: $store.askBeforeChainingExistingSystemProxy) {
                Label("Ask before chaining existing system proxy", systemImage: "questionmark.bubble")
                    .font(.sora(11, weight: .medium))
            }
            .toggleStyle(.checkbox)
        case .manual:
            EmptyView()
        case .off:
            NetworkInlineMessage(text: "Direct outbound route selected.", tint: Color.stxMuted, symbol: "arrow.forward")
        }
    }

    private var manualUpstreamProxyFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Route")
                .font(.sora(12, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Picker("Protocol", selection: $store.manualUpstreamProxyProtocol) {
                    ForEach(NetworkUpstreamProxyProtocol.allCases) { proto in
                        Text(proto.title).tag(proto)
                    }
                }
                .frame(width: 110)

                if store.manualUpstreamProxyProtocol == .pac {
                    TextField("PAC URL", text: $store.manualUpstreamProxyPACURL)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Host", text: $store.manualUpstreamProxyHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $store.manualUpstreamProxyPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                }
            }

            if store.manualUpstreamProxyProtocol != .pac {
                HStack(spacing: 8) {
                    TextField("Username", text: $store.manualUpstreamProxyUsername)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $store.manualUpstreamProxyPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .font(.sora(11))
    }

    private var routeScopeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route Scope")
                .font(.sora(12, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                TextField("Include hosts", text: $store.manualUpstreamProxyIncludeHosts)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.upstreamProxyMode != .manual)
                TextField("Exclude hosts", text: $store.manualUpstreamProxyExcludeHosts)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.upstreamProxyMode != .manual)
            }

            HStack(spacing: 16) {
                Toggle("Bypass localhost", isOn: $store.manualUpstreamBypassLocalhost)
                    .toggleStyle(.checkbox)
                    .disabled(store.upstreamProxyMode != .manual)
                Toggle("DNS over SOCKS", isOn: $store.manualUpstreamDNSOverSOCKS)
                    .toggleStyle(.checkbox)
                    .disabled(store.upstreamProxyMode != .manual || store.manualUpstreamProxyProtocol != .socks5)
            }
            .font(.sora(11, weight: .medium))
        }
        .font(.sora(11))
    }

    private var upstreamBadgeText: String {
        if store.upstreamProxyTestResult?.isReachable == true { return "Reachable" }
        if store.upstreamProxyTestResult?.isReachable == false { return "Failed" }
        if store.systemProxyStatus.upstreamProxySummary != nil { return "Chained" }
        return store.upstreamProxyMode == .off ? "Direct" : "Ready"
    }

    private var upstreamBadgeSymbol: String {
        if store.upstreamProxyTestResult?.isReachable == false { return "exclamationmark.triangle.fill" }
        if store.upstreamProxyMode == .off { return "arrow.forward.circle" }
        return "arrow.triangle.branch"
    }

    private var upstreamBadgeTint: Color {
        if store.upstreamProxyTestResult?.isReachable == true { return .green }
        if store.upstreamProxyTestResult?.isReachable == false { return .red }
        return store.systemProxyStatus.upstreamProxySummary != nil ? .green : Color.stxMuted
    }

    private var routeSummary: String {
        if let summary = store.systemProxyStatus.upstreamProxySummary { return summary }
        switch store.upstreamProxyMode {
        case .automatic:
            return "Auto detect"
        case .manual:
            return manualRouteSummary
        case .off:
            return "Direct"
        }
    }

    private var manualRouteSummary: String {
        switch store.manualUpstreamProxyProtocol {
        case .pac:
            let pac = store.manualUpstreamProxyPACURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return pac.isEmpty ? "PAC not configured" : "PAC \(pac)"
        case .http, .https, .socks5:
            let host = store.manualUpstreamProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? "\(store.manualUpstreamProxyProtocol.title) not configured" : "\(store.manualUpstreamProxyProtocol.title) \(host):\(store.manualUpstreamProxyPortText)"
        }
    }

    private var localhostBypassText: String {
        store.manualUpstreamBypassLocalhost ? "Bypass" : "Route"
    }

    private var socksDNSText: String {
        store.manualUpstreamProxyProtocol == .socks5 && store.manualUpstreamDNSOverSOCKS ? "Remote" : "Local"
    }
}

struct NetworkHelperView: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Privileged Helper", systemImage: "wrench.and.screwdriver")
                    .font(.sora(14, weight: .semibold))
                NetworkStatusBadge(
                    text: helperBadgeText,
                    symbol: store.helperState.canUsePrivilegedHelper ? "checkmark.seal.fill" : "wrench.and.screwdriver",
                    tint: store.helperState.canUsePrivilegedHelper ? .green : Color.stxMuted
                )
                Spacer()
                Button {
                    store.refreshHelperStatus()
                } label: {
                    Label("Check", systemImage: "arrow.clockwise")
                }
                .font(.sora(10, weight: .medium))
                .disabled(store.isHelperWorking)
            }

            NetworkInfoGrid(items: helperInfoItems)

            if let detail = store.helperState.detailMessage, !detail.isEmpty {
                NetworkInlineMessage(text: detail, tint: .red, symbol: "exclamationmark.triangle")
            }

            helperActions
        }
        .mainWindowPanel()
    }

    private var helperActions: some View {
        HStack(spacing: 10) {
            Spacer()

            if let action = store.helperState.action {
                Button {
                    store.performHelperAction(action)
                } label: {
                    Label(action.title, systemImage: helperActionSymbol(action))
                }
                .disabled(store.isHelperWorking)
            }

            Button {
                store.performHelperAction(.reinstall)
            } label: {
                Label("Reinstall", systemImage: "arrow.clockwise.circle")
            }
            .disabled(!canRunPrivilegedHelperAction || store.helperState.installedVersion == nil || store.isHelperWorking)

            Button {
                store.performHelperAction(.openSettings)
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .disabled(!canRunPrivilegedHelperAction || store.isHelperWorking)
        }
        .font(.sora(11, weight: .medium))
    }

    private var helperInfoItems: [NetworkInfoItem] {
        [
            NetworkInfoItem(title: "Status", value: store.helperState.statusMessage, symbol: "checklist"),
            NetworkInfoItem(title: "Registration", value: store.helperState.registrationStatus, symbol: "list.bullet.clipboard"),
            NetworkInfoItem(title: "Reachable", value: store.helperState.isReachable ? "Yes" : "No", symbol: "antenna.radiowaves.left.and.right"),
            NetworkInfoItem(title: "Bundled", value: bundledHelperText, symbol: "shippingbox"),
            NetworkInfoItem(title: "Installed", value: installedHelperText, symbol: "externaldrive.badge.checkmark"),
            NetworkInfoItem(title: "Protocol", value: helperProtocolText, symbol: "point.3.connected.trianglepath.dotted"),
        ]
    }

    private var helperBadgeText: String {
        if store.helperState.canUsePrivilegedHelper { return "Ready" }
        if store.helperState.statusID == "disabledForUnsignedBuild" { return "Embedded" }
        return "Limited"
    }

    private var bundledHelperText: String {
        "\(store.helperState.bundledVersion) (\(store.helperState.bundledBuild))"
    }

    private var installedHelperText: String {
        guard let version = store.helperState.installedVersion else { return "Not installed" }
        if let build = store.helperState.installedBuild {
            return "\(version) (\(build))"
        }
        return version
    }

    private var helperProtocolText: String {
        let installed = store.helperState.installedProtocolVersion.map(String.init) ?? "-"
        return "\(installed) / \(store.helperState.expectedProtocolVersion)"
    }

    private var canRunPrivilegedHelperAction: Bool {
        store.helperState.statusID != "disabledForUnsignedBuild"
    }

    private func helperActionSymbol(_ action: NetworkHelperAction) -> String {
        switch action {
        case .install: "square.and.arrow.down"
        case .check: "arrow.clockwise"
        case .update: "arrow.down.circle"
        case .retry: "arrow.clockwise.circle"
        case .reinstall: "arrow.triangle.2.circlepath"
        case .openSettings: "gear"
        }
    }
}

private struct NetworkStatusBadge: View {
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.sora(10, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct NetworkInfoItem: Hashable {
    var title: String
    var value: String
    var symbol: String
}

private struct NetworkInfoGrid: View {
    var items: [NetworkInfoItem]
    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .topLeading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.uppercased())
                            .font(.sora(9, weight: .semibold))
                            .foregroundStyle(Color.stxMuted)
                        Text(item.value)
                            .font(.sora(11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }
}

private struct NetworkInlineMessage: View {
    var text: String
    var tint: Color
    var symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.sora(11))
            .foregroundStyle(tint)
            .lineLimit(2)
            .textSelection(.enabled)
    }
}

struct NetworkCertificatesView: View {
    @Bindable var store: NetworkDebuggerStore
    @State private var newHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            caCard
            mitmCard
        }
    }

    private var caCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Root CA", systemImage: "checkmark.shield")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Text(store.certificateState.isTrusted ? "Trusted" : "Not trusted")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(store.certificateState.isTrusted ? .green : Color.stxMuted)
            }

            if let path = store.certificateState.rootCAPath {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.stxMuted)
                    .textSelection(.enabled)
            } else {
                Text("Generate a local root certificate before enabling HTTPS inspection.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 10) {
                Button {
                    store.generateRootCA()
                } label: {
                    Label("Generate Root CA", systemImage: "plus")
                }
                .disabled(store.isCertificateWorking)

                Button {
                    store.trustRootCA()
                } label: {
                    Label("Trust in Keychain", systemImage: "key")
                }
                .disabled(store.certificateState.rootCAPath == nil || store.isCertificateWorking)
            }
            .font(.sora(11, weight: .medium))

            if let message = store.certificateState.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .mainWindowPanel()
    }

    private var mitmCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("HTTPS MITM", systemImage: "lock.open")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Toggle("", isOn: $store.certificateState.isMITMEnabled)
                    .labelsHidden()
            }

            Text("Only hosts in the allowlist are eligible for HTTPS decryption. The first proxy version records CONNECT metadata when interception is not available.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)

            HStack(spacing: 8) {
                TextField("api.example.com", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.addSSLHost(newHost)
                    newHost = ""
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add host")
            }

            if store.certificateState.sslHostAllowlist.isEmpty {
                Text("No SSL hosts yet")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(store.certificateState.sslHostAllowlist, id: \.self) { host in
                        HStack(spacing: 6) {
                            Text(host)
                                .font(.sora(11))
                            Button {
                                store.removeSSLHost(host)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
        .mainWindowPanel()
    }
}

struct NetworkRulesView: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                rulesList
                    .frame(width: 280)
                ruleEditor
                    .frame(minWidth: 520, maxWidth: .infinity)
            }
            breakpointsPanel
            pluginsPanel
        }
        .task {
            store.refreshRules()
            store.refreshPlugins()
            store.refreshBreakpoints()
        }
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rules", systemImage: "slider.horizontal.3")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(NetworkRuleActionKind.allCases) { kind in
                        Button(kind.title) { store.createRule(kind: kind) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            VStack(spacing: 4) {
                ForEach(store.rules) { rule in
                    ruleRow(rule)
                }
            }

            HStack(spacing: 8) {
                Button {
                    store.exportRulesToPasteboard()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button {
                    store.importRulesFromPasteboard()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            .font(.sora(10, weight: .medium))

            if let message = store.ruleStatusMessage {
                Text(message)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
        }
        .mainWindowPanel()
    }

    private func ruleRow(_ rule: NetworkRuleDraft) -> some View {
        Button {
            store.selectedRuleID = rule.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(rule.isEnabled ? Color.green : Color.stxMuted.opacity(0.45))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(.sora(11, weight: .semibold))
                        .lineLimit(1)
                    Text(rule.summary)
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                if store.selectedRuleID == rule.id {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var ruleEditor: some View {
        if store.selectedRule != nil {
            VStack(alignment: .leading, spacing: 14) {
                editorHeader
                matchEditor
                actionEditor
                editorFooter
            }
            .mainWindowPanel()
        } else {
            Text("Create a rule to begin.")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .frame(maxWidth: .infinity, minHeight: 80)
                .mainWindowPanel()
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            TextField("Rule name", text: binding(\.name))
                .textFieldStyle(.roundedBorder)
                .font(.sora(13, weight: .semibold))
            Toggle("Enabled", isOn: binding(\.isEnabled))
                .toggleStyle(.checkbox)
                .onChange(of: store.selectedRule?.isEnabled ?? false) { _, enabled in
                    if let rule = store.selectedRule {
                        store.setRuleEnabled(rule, enabled: enabled)
                    }
                }
        }
    }

    private var matchEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MATCH")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            HStack(spacing: 8) {
                Picker("Method", selection: binding(\.method)) {
                    ForEach(NetworkRuleMatchMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .frame(width: 130)
                TextField("URL regex", text: binding(\.urlPattern))
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                TextField("Header name", text: binding(\.headerName))
                    .textFieldStyle(.roundedBorder)
                TextField("Header value", text: binding(\.headerValue))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var actionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTION")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Picker("Action", selection: actionBinding(\.kind)) {
                ForEach(NetworkRuleActionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .frame(width: 220)

            switch store.selectedRule?.action.kind ?? .block {
            case .block:
                Stepper("Status \(store.selectedRule?.action.blockStatusCode ?? 403)", value: actionBinding(\.blockStatusCode), in: 0...599)
            case .mapLocal:
                localMappingEditor
            case .mapRemote:
                remoteMappingEditor
            case .modifyHeaders:
                headerOperationsEditor
            case .throttle:
                Stepper("Delay \(store.selectedRule?.action.throttleDelayMs ?? 500) ms", value: actionBinding(\.throttleDelayMs), in: 0...60_000, step: 100)
            case .networkCondition:
                HStack {
                    TextField("Preset", text: actionBinding(\.networkConditionName))
                        .textFieldStyle(.roundedBorder)
                    Stepper("Delay \(store.selectedRule?.action.networkConditionDelayMs ?? 1_000) ms", value: actionBinding(\.networkConditionDelayMs), in: 0...120_000, step: 100)
                }
            case .breakpoint:
                Picker("Phase", selection: actionBinding(\.breakpointPhase)) {
                    ForEach(NetworkBreakpointPhase.allCases) { phase in
                        Text(phase.rawValue.capitalized).tag(phase)
                    }
                }
                .frame(width: 180)
            case .script:
                scriptEditor
            }
        }
    }

    private var localMappingEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("File or directory path", text: actionBinding(\.mapLocalPath))
                    .textFieldStyle(.roundedBorder)
                Button {
                    chooseLocalPath()
                } label: {
                    Label("Choose", systemImage: "folder")
                }
            }
            HStack {
                Stepper("Status \(store.selectedRule?.action.mapLocalStatusCode ?? 200)", value: actionBinding(\.mapLocalStatusCode), in: 100...599)
                Toggle("Directory", isOn: actionBinding(\.mapLocalIsDirectory))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var remoteMappingEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Scheme", text: actionBinding(\.mapRemoteScheme))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("Host", text: actionBinding(\.mapRemoteHost))
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: actionBinding(\.mapRemotePortText))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
            }
            HStack(spacing: 8) {
                TextField("Path", text: actionBinding(\.mapRemotePath))
                    .textFieldStyle(.roundedBorder)
                TextField("Query", text: actionBinding(\.mapRemoteQuery))
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Preserve Host header", isOn: actionBinding(\.mapRemotePreserveHostHeader))
                .toggleStyle(.checkbox)
        }
    }

    private var headerOperationsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.selectedRule?.action.headerOperations ?? []) { operation in
                HStack(spacing: 8) {
                    Picker("", selection: headerOperationBinding(operation.id, \.kind)) {
                        ForEach(NetworkHeaderOperationKind.allCases) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    .frame(width: 105)
                    Picker("", selection: headerOperationBinding(operation.id, \.phase)) {
                        ForEach(NetworkHeaderOperationPhase.allCases) { phase in
                            Text(phase.rawValue.capitalized).tag(phase)
                        }
                    }
                    .frame(width: 110)
                    TextField("Header", text: headerOperationBinding(operation.id, \.name))
                        .textFieldStyle(.roundedBorder)
                    TextField("Value", text: headerOperationBinding(operation.id, \.value))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        removeHeaderOperation(operation.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                addHeaderOperation()
            } label: {
                Label("Add Header Operation", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var scriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: actionBinding(\.scriptMode)) {
                    ForEach(NetworkScriptRuleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Request", isOn: actionBinding(\.scriptRunOnRequest))
                    .toggleStyle(.checkbox)
                Toggle("Response", isOn: actionBinding(\.scriptRunOnResponse))
                    .toggleStyle(.checkbox)
            }
            TextEditor(text: actionBinding(\.scriptSource))
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Button {
                store.saveSelectedRule()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button {
                store.duplicateSelectedRule()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                store.deleteSelectedRule()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Spacer()

            Button {
                store.moveSelectedRuleUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            Button {
                store.moveSelectedRuleDown()
            } label: {
                Image(systemName: "arrow.down")
            }
            Button {
                store.testSelectedRuleAgainstSelectedFlow()
            } label: {
                Label("Test", systemImage: "checkmark.circle")
            }
        }
        .font(.sora(10, weight: .medium))
        .overlay(alignment: .bottomLeading) {
            if let result = store.ruleMatchResult {
                Text(result.message)
                    .font(.sora(10))
                    .foregroundStyle(result.matches ? .green : Color.stxMuted)
                    .offset(y: 24)
            }
        }
    }

    private var pluginsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Plugins", systemImage: "puzzlepiece.extension")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    installPlugin()
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
                Button {
                    store.refreshPlugins()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .font(.sora(10, weight: .medium))

            if store.plugins.isEmpty {
                Text("No plugins installed.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.plugins) { plugin in
                        pluginRow(plugin)
                    }
                }
            }

            if let message = store.pluginStatusMessage {
                Text(message)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .mainWindowPanel()
    }

    private var breakpointsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Breakpoints", systemImage: "pause.circle")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    store.refreshBreakpoints()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .font(.sora(10, weight: .medium))

            if store.breakpoints.isEmpty {
                Text("No paused breakpoint requests.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.breakpoints) { item in
                        breakpointRow(item)
                    }
                }
            }
        }
        .mainWindowPanel()
    }

    private func breakpointRow(_ item: NetworkBreakpointItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.phase.rawValue.capitalized)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(item.title)
                    .font(.sora(11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let statusCode = item.statusCode, item.phase != .request {
                    Text("\(statusCode)")
                        .font(.sora(10, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }
            }

            HStack(spacing: 8) {
                TextField("Method", text: breakpointStringBinding(item.id, \.method, fallback: item.method))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 95)
                TextField("URL", text: breakpointStringBinding(item.id, \.url, fallback: item.url))
                    .textFieldStyle(.roundedBorder)
            }

            if !item.body.isEmpty {
                TextEditor(text: breakpointStringBinding(item.id, \.body, fallback: item.body))
                    .font(.system(size: 10, design: .monospaced))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button {
                    store.resolveBreakpoint(item, decision: .execute)
                } label: {
                    Label("Continue", systemImage: "play.fill")
                }
                Button(role: .destructive) {
                    store.resolveBreakpoint(item, decision: .abort)
                } label: {
                    Label("Drop", systemImage: "xmark")
                }
                Button {
                    store.resolveBreakpoint(item, decision: .cancel)
                } label: {
                    Label("Cancel", systemImage: "arrow.uturn.backward")
                }
                Spacer()
            }
            .font(.sora(10, weight: .medium))
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func pluginRow(_ plugin: NetworkPluginItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { store.setPluginEnabled(plugin, enabled: $0) }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plugin.name) \(plugin.version)")
                    .font(.sora(11, weight: .semibold))
                Text(plugin.summary)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Spacer()
            Text(plugin.statusMessage)
                .font(.sora(10))
                .foregroundStyle(plugin.status == .error ? .red : Color.stxMuted)
            Button {
                store.reloadPlugin(plugin)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                store.deletePlugin(plugin)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NetworkRuleDraft, Value>) -> Binding<Value> {
        Binding {
            store.selectedRule?[keyPath: keyPath] ?? NetworkRuleDraft()[keyPath: keyPath]
        } set: { value in
            store.updateSelectedRule { $0[keyPath: keyPath] = value }
        }
    }

    private func actionBinding<Value>(_ keyPath: WritableKeyPath<NetworkRuleActionDraft, Value>) -> Binding<Value> {
        Binding {
            store.selectedRule?.action[keyPath: keyPath] ?? NetworkRuleActionDraft()[keyPath: keyPath]
        } set: { value in
            store.updateSelectedRule { $0.action[keyPath: keyPath] = value }
        }
    }

    private func headerOperationBinding<Value>(
        _ id: UUID,
        _ keyPath: WritableKeyPath<NetworkHeaderOperationDraft, Value>
    ) -> Binding<Value> {
        Binding {
            store.selectedRule?.action.headerOperations.first { $0.id == id }?[keyPath: keyPath]
                ?? NetworkHeaderOperationDraft()[keyPath: keyPath]
        } set: { value in
            store.updateSelectedRule { rule in
                guard let index = rule.action.headerOperations.firstIndex(where: { $0.id == id }) else { return }
                rule.action.headerOperations[index][keyPath: keyPath] = value
            }
        }
    }

    private func breakpointStringBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<NetworkBreakpointItem, String>,
        fallback: String
    ) -> Binding<String> {
        Binding {
            store.breakpoints.first { $0.id == id }?[keyPath: keyPath] ?? fallback
        } set: { value in
            guard var item = store.breakpoints.first(where: { $0.id == id }) else { return }
            item[keyPath: keyPath] = value
            store.updateBreakpoint(item)
        }
    }

    private func addHeaderOperation() {
        store.updateSelectedRule { $0.action.headerOperations.append(NetworkHeaderOperationDraft()) }
    }

    private func removeHeaderOperation(_ id: UUID) {
        store.updateSelectedRule { rule in
            rule.action.headerOperations.removeAll { $0.id == id }
            if rule.action.headerOperations.isEmpty {
                rule.action.headerOperations.append(NetworkHeaderOperationDraft())
            }
        }
    }

    private func chooseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.updateSelectedRule { $0.action.mapLocalPath = url.path }
        }
    }

    private func installPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.installPlugin(at: url.path)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
