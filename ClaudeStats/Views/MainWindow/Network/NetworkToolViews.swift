import SwiftUI

struct NetworkSetupView: View {
    @Bindable var store: NetworkDebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            commandsCard
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Local Proxy", systemImage: "network")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Text(store.statusMessage)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 10) {
                Button {
                    store.startCapture()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(store.captureStatus.isListening)

                Button {
                    store.stopCapture()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!store.captureStatus.isListening)

                Spacer()

                Button {
                    store.enableSystemProxy()
                } label: {
                    Label("Enable System Proxy", systemImage: "switch.2")
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

            Toggle(isOn: $store.autoEnableSystemProxyOnStart) {
                Label("Auto-enable system proxy on start", systemImage: "bolt.horizontal")
                    .font(.sora(11, weight: .medium))
            }
            .toggleStyle(.checkbox)

            if let error = store.systemProxyStatus.lastError, !error.isEmpty {
                Text(error)
                    .font(.sora(11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.systemProxyStatus.isEnabled {
                Text("Managed services: \(store.systemProxyStatus.managedServices.joined(separator: ", "))")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
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

    private func command(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
    private let rules = [
        ("Rewrite", "Modify request or response headers and bodies.", "arrow.triangle.2.circlepath"),
        ("Map Local", "Serve local files for matching URLs.", "folder"),
        ("Breakpoints", "Pause requests or responses before forwarding.", "pause.rectangle"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(rules, id: \.0) { rule in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: rule.2)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.stxAccent)
                    Text(rule.0)
                        .font(.sora(14, weight: .semibold))
                    Text(rule.1)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                    Spacer(minLength: 0)
                    Text("Coming next")
                        .font(.sora(10, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                }
                .frame(minHeight: 130, alignment: .topLeading)
                .mainWindowPanel()
            }
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
