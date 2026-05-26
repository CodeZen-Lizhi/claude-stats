import SwiftUI

struct OpsBrewView: View {
    @Bindable var store: OpsStore
    @State private var installText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                OpsSearchField(text: $store.brewQuery, placeholder: "Search packages")
                Button {
                    store.refresh(.brew)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            OpsCard {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Homebrew")
                            .font(.sora(14, weight: .semibold))
                        Text(store.brewSnapshot.brewPath ?? "Not found")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }

            if !store.brewSnapshot.errors.isEmpty {
                OpsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Command errors")
                            .font(.sora(13, weight: .semibold))
                        OpsCodeBlock(store.brewSnapshot.errors.joined(separator: "\n"))
                    }
                }
            }

            if let output = store.lastActionOutput, !output.isEmpty {
                OpsActionOutputCard(output: output) {
                    store.clearActionOutput()
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Install")
                        .font(.sora(13, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("package-name", text: $installText)
                            .textFieldStyle(.roundedBorder)
                            .font(.sora(12))
                        Button {
                            store.requestBrewInstall(installText)
                        } label: {
                            Label("Install", systemImage: "plus")
                        }
                        .controlSize(.small)
                        .disabled(store.brewSnapshot.brewPath == nil || !store.canRunAction || installText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Packages")
                            .font(.sora(13, weight: .semibold))
                        Spacer()
                        Text("\(store.filteredBrewPackages.count)")
                            .font(.sora(11).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                    }

                    if store.filteredBrewPackages.isEmpty {
                        OpsInlineEmptyState("No packages.")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(store.filteredBrewPackages) { package in
                                OpsBrewPackageRow(package: package, isSelected: store.selectedBrewPackage?.id == package.id, actionsDisabled: !store.canRunAction) {
                                    store.selectBrewPackage(package)
                                } upgrade: {
                                    store.requestBrewUpgrade(package)
                                } uninstall: {
                                    store.requestBrewUninstall(package)
                                }
                            }
                        }
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Services")
                        .font(.sora(13, weight: .semibold))
                    if store.brewSnapshot.services.isEmpty {
                        OpsInlineEmptyState("No Homebrew services.")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(store.brewSnapshot.services) { service in
                                OpsBrewServiceRow(service: service, actionsDisabled: !store.canRunAction) { action in
                                    store.requestBrewService(service.name, action: action)
                                }
                            }
                        }
                    }
                }
            }

            OpsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Doctor")
                        .font(.sora(13, weight: .semibold))
                    OpsCodeBlock(store.brewSnapshot.doctorOutput)
                }
            }
        }
    }
}

struct OpsEnvironmentView: View {
    @Bindable var store: OpsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Developer tools")
                    .font(.sora(14, weight: .semibold))
                Spacer()
                Button {
                    store.refresh(.environment)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(store.environmentTools) { tool in
                    OpsEnvironmentToolCard(tool: tool)
                }
            }
        }
    }
}

private struct OpsSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
    }
}

private struct OpsBrewPackageRow: View {
    let package: OpsBrewPackage
    let isSelected: Bool
    let actionsDisabled: Bool
    let select: () -> Void
    let upgrade: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: package.kind == .formula ? "shippingbox" : "app.dashed")
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name)
                            .font(.sora(12, weight: .medium))
                        Text(package.installedVersion)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer()
                    if package.isOutdated {
                        OpsMiniBadge(package.latestVersion ?? "update")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: upgrade) {
                Image(systemName: "arrow.up.circle")
            }
            .buttonStyle(.plain)
            .disabled(!package.isOutdated || actionsDisabled)
            .help("Upgrade")

            Button(role: .destructive, action: uninstall) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(actionsDisabled)
            .help("Uninstall")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08))
            }
        }
    }
}

private struct OpsBrewServiceRow: View {
    let service: OpsBrewServiceItem
    let actionsDisabled: Bool
    let action: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.status.lowercased().contains("started") ? Color.green : Color.stxMuted.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.sora(12, weight: .medium))
                Text([service.status, service.user, service.file].compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }.joined(separator: " · "))
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(OpsBrewServiceAction.allCases) { item in
                    Button(item.rawValue.capitalized) { action(item.rawValue) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .disabled(actionsDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct OpsEnvironmentToolCard: View {
    let tool: OpsEnvironmentTool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.sora(12, weight: .semibold))
                    Text(tool.command)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer()
                OpsMiniBadge(tool.status.title)
            }

            if let version = tool.version {
                OpsCodeBlock(version)
            }
            if let path = tool.resolvedPath {
                OpsKeyValue("Path", path)
            }
            if let detail = tool.detail {
                Text(detail)
                    .font(.sora(10))
                    .foregroundStyle(tool.isTrustedPath ? Color.stxMuted : Color.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusSymbol: String {
        switch tool.status {
        case .available: "checkmark.circle.fill"
        case .missing: "minus.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .available: .green
        case .missing: Color.stxMuted
        case .error: .orange
        }
    }
}

private struct OpsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mainWindowPanel()
    }
}

private struct OpsActionOutputCard: View {
    let output: String
    let dismiss: () -> Void

    var body: some View {
        OpsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last action")
                        .font(.sora(13, weight: .semibold))
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                OpsCodeBlock(output)
            }
        }
    }
}

private struct OpsKeyValue: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct OpsCodeBlock: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.isEmpty ? "--" : text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct OpsInlineEmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.sora(11))
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
    }
}

private struct OpsMiniBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
