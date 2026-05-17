import SwiftUI

struct ConfigurationsView: View {
    @Environment(AppEnvironment.self) private var env

    private let workspaceMaxWidth: CGFloat = 980
    private let railColumnWidth: CGFloat = 78
    private let providerColumnWidth: CGFloat = 330
    private let columnSpacing: CGFloat = 14
    private let railMinimumHeight: CGFloat = 144
    private let editorModeContentHeight: CGFloat = 176

    @State private var editorMode: APIProviderEditorMode = .fields
    @State private var cursorLine = 1
    @State private var cursorColumn = 1

    var body: some View {
        @Bindable var vm = env.apiProviders

        CenteredPaneContainer(maxWidth: workspaceMaxWidth, topPadding: 36) {
            VStack(alignment: .leading, spacing: 18) {
                header(vm: vm)
                APIProviderWorkspaceLayout(
                    railWidth: railColumnWidth,
                    providerWidth: providerColumnWidth,
                    editorMinWidth: providerColumnWidth,
                    spacing: columnSpacing
                ) {
                    cliRail(vm: vm)
                    providersColumn(vm: vm)
                    editorColumn(vm: vm)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .task {
            await vm.loadIfNeeded(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
        }
        .onChange(of: env.preferences.apiProviderKeyStorageMode) { _, newMode in
            Task { await vm.reload(keyStorageMode: newMode) }
        }
        .alert("Configuration Error", isPresented: errorBinding) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    private func header(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Provider Switcher")
                    .font(.sora(28, weight: .semibold))
                HStack(spacing: 8) {
                    Text(vm.selectedCLI.displayName)
                    Text("·")
                    Text(env.preferences.apiProviderKeyStorageMode.displayName)
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            if vm.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func cliRail(vm: APIProviderSwitcherViewModel) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                ForEach(APIProviderCLI.allCases) { cli in
                    Button {
                        editorMode = .fields
                        vm.selectCLI(cli, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    } label: {
                        Image(cli.assetName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(vm.selectedCLI == cli ? Color.stxAccent : Color.stxMuted)
                            .frame(width: 54, height: 54)
                            .background {
                                if vm.selectedCLI == cli {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.stxAccent.opacity(0.14))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(vm.selectedCLI == cli ? Color.stxAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(cli.displayName)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
        .frame(width: railColumnWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private func providersColumn(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Providers")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task { await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                } label: {
                    Label("Import Current", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Menu {
                    Button {
                        Task { await vm.addProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                    } label: {
                        Label("Provider", systemImage: "plus")
                    }
                    Button {
                        Task { await vm.addUniversalProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                    } label: {
                        Label("Universal Provider", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.button)
                .controlSize(.small)
                .disabled(vm.isWorking)
                .help("New provider")
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        let providers = vm.providers(for: vm.selectedCLI)
                        if providers.isEmpty {
                            Text("No providers")
                                .font(.sora(12))
                                .foregroundStyle(Color.stxMuted)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(providers) { provider in
                                APIProviderListRow(
                                    provider: provider,
                                    isSelected: vm.selectedProviderID == provider.id,
                                    isActive: vm.isActive(provider)
                                ) {
                                    editorMode = .fields
                                    vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                                }
                                if provider.id != providers.last?.id {
                                    StxRule().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))

                    if let result = vm.latestApplyResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last backup")
                                .font(.sora(10, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(result.backupDirectory.path)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.stxPanel.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.automatic)
        }
        .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func editorColumn(vm: APIProviderSwitcherViewModel) -> some View {
        editorPanel(vm: vm)
            .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func editorPanel(vm: APIProviderSwitcherViewModel) -> some View {
        if vm.draftProviderID == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("No provider selected")
                    .font(.sora(16, weight: .semibold))
                Text("Create or import a provider.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                editorHeader(vm: vm)
                Picker("", selection: $editorMode) {
                    ForEach(APIProviderEditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                if editorMode == .fields {
                    providerFields(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                } else {
                    rawEditor(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                }

                editorActions(vm: vm)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
        }
    }

    private func editorHeader(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(vm.draftCLI.assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.stxAccent)
            VStack(alignment: .leading, spacing: 7) {
                Text(vm.draftName.isEmpty ? "Provider" : vm.draftName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    APIProviderBadge(title: vm.draftOrigin?.displayName ?? "Provider")
                    APIProviderBadge(title: vm.draftCategory.displayName)
                    if let provider = vm.selectedProvider, vm.isActive(provider) {
                        APIProviderBadge(title: "Active", tint: Color.stxAccent)
                    }
                    if vm.draftIsDirty {
                        APIProviderBadge(title: "Unsaved", tint: .orange)
                    }
                }
            }
            Spacer(minLength: 12)
        }
    }

    private func providerFields(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isOfficial = bindableVM.draftOrigin?.kind == .official
        let isUniversal = bindableVM.draftOrigin?.kind == .universal

        return VStack(alignment: .leading, spacing: 12) {
            APIProviderFieldRow(title: "Name") {
                TextField("Provider name", text: $bindableVM.draftName)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Category") {
                Picker("", selection: $bindableVM.draftCategory) {
                    ForEach(APIProviderCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .labelsHidden()
                .disabled(isUniversal)
            }
            APIProviderFieldRow(title: "Base URL") {
                TextField("https://api.example.com", text: $bindableVM.draftBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "API Key") {
                SecureField("API key", text: $bindableVM.draftAPIKey)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Model") {
                TextField(bindableVM.draftCLI == .claude ? "claude-compatible model" : "gpt-compatible model", text: $bindableVM.draftModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
            .disabled(isOfficial || bindableVM.isWorking)
    }

    private func rawEditor(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isEditable = bindableVM.canSaveSelectedProvider && !bindableVM.isWorking

        return VStack(alignment: .leading, spacing: 8) {
            ConfigurationTextEditor(
                text: $bindableVM.draftRawConfig,
                fileKind: bindableVM.draftCLI == .claude ? .json : .toml,
                isEditable: isEditable
            ) { line, column in
                cursorLine = line
                cursorColumn = column
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))

            HStack(spacing: 8) {
                Text(bindableVM.draftCLI == .claude ? "settings.json" : "config.toml")
                Text("·")
                Text("\(cursorLine):\(cursorColumn)")
                Spacer(minLength: 8)
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
        }
    }

    private func editorActions(vm: APIProviderSwitcherViewModel) -> some View {
        ViewThatFits(in: .horizontal) {
            editorActionButtons(vm: vm, showLabels: true)
            editorActionButtons(vm: vm, showLabels: false)
        }
        .controlSize(.small)
    }

    private func editorActionButtons(vm: APIProviderSwitcherViewModel, showLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                Task { await vm.deleteSelectedProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
            } label: {
                actionLabel("Delete", systemImage: "trash", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canDeleteSelectedProvider || vm.isWorking)
            .help("Delete")

            Spacer(minLength: 12)

            Button {
                vm.resetDraft(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
            } label: {
                actionLabel("Revert", systemImage: "arrow.uturn.backward", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.draftIsDirty || vm.isWorking)
            .help("Revert")

            Button {
                Task {
                    await vm.saveDraft(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                }
            } label: {
                actionLabel("Save Provider", systemImage: "square.and.arrow.down", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canSaveSelectedProvider || !vm.draftIsDirty || vm.isWorking)
            .help("Save Provider")

            Button {
                Task {
                    await vm.enableSelectedProvider(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                }
            } label: {
                actionLabel("Enable Provider", systemImage: "bolt.fill", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedProvider == nil || vm.isWorking)
            .help("Enable Provider")
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String, showLabels: Bool) -> some View {
        if showLabels {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .frame(width: 22, height: 18)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { env.apiProviders.lastError != nil },
            set: { newValue in
                if !newValue { env.apiProviders.clearError() }
            }
        )
    }
}

private struct APIProviderWorkspaceLayout: Layout {
    let railWidth: CGFloat
    let providerWidth: CGFloat
    let editorMinWidth: CGFloat
    let spacing: CGFloat

    private var stackedSpacing: CGFloat {
        min(spacing, 8)
    }

    private var wideMinimumWidth: CGFloat {
        railWidth + providerWidth + editorMinWidth + spacing * 2
    }

    private var narrowWidth: CGFloat {
        railWidth + providerWidth + spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }

        let availableWidth = proposal.width ?? wideMinimumWidth
        if availableWidth >= wideMinimumWidth {
            let editorWidth = max(editorMinWidth, availableWidth - railWidth - providerWidth - spacing * 2)
            let editorSize = subviews[2].sizeThatFits(ProposedViewSize(width: editorWidth, height: nil))
            return CGSize(
                width: railWidth + providerWidth + editorWidth + spacing * 2,
                height: editorSize.height
            )
        } else {
            let layoutWidth = max(availableWidth, narrowWidth)
            let detailWidth = max(providerWidth, layoutWidth - railWidth - spacing)
            let editorSize = subviews[2].sizeThatFits(ProposedViewSize(width: detailWidth, height: nil))
            let providerHeight = narrowProviderHeight(subviews: subviews, width: detailWidth, maxHeight: editorSize.height)
            let stackedHeight = providerHeight + stackedSpacing + editorSize.height
            return CGSize(width: layoutWidth, height: stackedHeight)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }

        if bounds.width >= wideMinimumWidth {
            placeWide(in: bounds, subviews: subviews)
        } else {
            placeNarrow(in: bounds, subviews: subviews)
        }
    }

    private func placeWide(in bounds: CGRect, subviews: Subviews) {
        let editorWidth = max(editorMinWidth, bounds.width - railWidth - providerWidth - spacing * 2)
        let editorSize = subviews[2].sizeThatFits(ProposedViewSize(width: editorWidth, height: nil))
        let columnHeight = editorSize.height

        var x = bounds.minX
        subviews[0].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: railWidth, height: columnHeight)
        )

        x += railWidth + spacing
        subviews[1].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: providerWidth, height: columnHeight)
        )

        x += providerWidth + spacing
        subviews[2].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: editorWidth, height: nil)
        )
    }

    private func placeNarrow(in bounds: CGRect, subviews: Subviews) {
        let detailWidth = max(providerWidth, bounds.width - railWidth - spacing)
        let editorSize = subviews[2].sizeThatFits(ProposedViewSize(width: detailWidth, height: nil))
        let providerHeight = narrowProviderHeight(subviews: subviews, width: detailWidth, maxHeight: editorSize.height)
        let stackedHeight = providerHeight + stackedSpacing + editorSize.height
        let originX = bounds.minX
        let rightX = originX + railWidth + spacing

        subviews[0].place(
            at: CGPoint(x: originX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: railWidth, height: stackedHeight)
        )
        subviews[1].place(
            at: CGPoint(x: rightX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: providerHeight)
        )
        subviews[2].place(
            at: CGPoint(x: rightX, y: bounds.minY + providerHeight + stackedSpacing),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: nil)
        )
    }

    private func narrowProviderHeight(subviews: Subviews, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let naturalHeight = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return min(naturalHeight, maxHeight)
    }
}

private enum APIProviderEditorMode: String, CaseIterable, Identifiable {
    case fields
    case raw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fields: "Fields"
        case .raw: "Raw"
        }
    }
}

private struct APIProviderListRow: View {
    let provider: CLIAPIProvider
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(provider.cli.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    Text(provider.name)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isActive {
                        Circle()
                            .fill(Color.stxAccent)
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 6) {
                    APIProviderBadge(title: provider.origin.displayName)
                    if provider.category != .official && provider.category != .imported {
                        APIProviderBadge(title: provider.category.displayName)
                    }
                    Spacer(minLength: 6)
                }

                HStack(spacing: 6) {
                    Text(provider.baseURL.isEmpty ? "Official endpoint" : provider.baseURL)
                        .lineLimit(1)
                    if !provider.model.isEmpty {
                        Text("·")
                        Text(provider.model).lineLimit(1)
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct APIProviderFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 86, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct APIProviderBadge: View {
    let title: String
    var tint: Color = Color.stxMuted

    var body: some View {
        Text(title)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    ConfigurationsView()
        .environment(AppEnvironment.preview())
        .frame(width: 1180, height: 780)
}
#endif
