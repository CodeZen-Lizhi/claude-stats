import SwiftUI

struct LocalAIModelsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hfRepo = ""
    @State private var hfFile = ""
    @State private var hfRevision = "main"
    @State private var hfToken = ""
    @State private var advancedImportExpanded = false

    var body: some View {
        @Bindable var modelStore = env.localAI.modelStore

        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Models", caption: "Installed models add semantic search and similar-session matching without replacing the existing transcript analysis.") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(modelStore.allModels) { model in
                        LocalAIModelInstallCard(
                            model: model,
                            state: modelStore.installState(for: model.id),
                            isRecommended: model.id == modelStore.recommendedModelID,
                            isSelected: model.id == modelStore.selectedModelID,
                            onSelect: { modelStore.selectedModelID = model.id },
                            onDownload: { modelStore.download(modelID: model.id) },
                            onDelete: { modelStore.delete(modelID: model.id) }
                        )
                    }
                }
            }

            SettingGroup(title: "Vector Cache") {
                VStack(spacing: 0) {
                    SettingRow(
                        title: "Session embeddings",
                        description: "Cached per provider, session, model revision, chunk, and text hash."
                    ) {
                        Button {
                            env.localAI.deleteEmbeddingCache()
                        } label: {
                            Label("Delete Cache", systemImage: "trash")
                        }
                        .controlSize(.small)
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Advanced Import", caption: "Import a single GGUF file from Hugging Face when you want to test a model outside the built-in catalog.") {
                DisclosureGroup(isExpanded: $advancedImportExpanded) {
                    VStack(spacing: 0) {
                        SettingRow(title: "Repository", description: "For example: Qwen/Qwen3-Embedding-0.6B-GGUF") {
                            TextField("owner/repo", text: $hfRepo)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                        }
                        SettingRowDivider()
                        SettingRow(title: "GGUF file", description: "The exact file name to download.") {
                            TextField("model-Q8_0.gguf", text: $hfFile)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                        }
                        SettingRowDivider()
                        SettingRow(title: "Revision", description: "Branch, tag, or commit. Leave as main for most models.") {
                            TextField("main", text: $hfRevision)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                        }
                        SettingRowDivider()
                        SettingRow(title: "Token", description: "Optional. Used only for this download.") {
                            SecureField("hf_...", text: $hfToken)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                        }
                        SettingRowDivider()
                        SettingRow(title: "Import model") {
                            Button {
                                modelStore.addHuggingFaceModel(
                                    repo: hfRepo,
                                    file: hfFile,
                                    revision: hfRevision,
                                    token: hfToken
                                )
                                hfToken = ""
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .controlSize(.small)
                            .disabled(hfRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hfFile.hasSuffix(".gguf"))
                        }
                    }
                    .settingCard()
                    .padding(.top, 10)
                } label: {
                    Label("Hugging Face GGUF", systemImage: "shippingbox")
                        .font(.sora(13, weight: .medium))
                }
            }

            if let error = env.localAI.lastSemanticError {
                Text(error)
                    .font(.sora(11))
                    .foregroundStyle(Color.red)
                    .padding(12)
                    .settingCard()
            }
        }
    }
}

private struct LocalAIModelInstallCard: View {
    let model: LocalAIModelManifest
    let state: LocalModelInstallState
    let isRecommended: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.isExperimental ? "flask" : "brain")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.isExperimental ? Color.orange : Color.stxAccent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(.sora(14, weight: .semibold))
                            .lineLimit(1)
                        if isRecommended {
                            LocalAIStatusPill(text: "Recommended", tone: .accent)
                        }
                        if model.isExperimental {
                            LocalAIStatusPill(text: "Phase 3", tone: .warning)
                        }
                        if isSelected {
                            LocalAIStatusPill(text: "Selected", tone: .neutral)
                        }
                    }
                    Text(model.subtitle)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    metadata
                }

                Spacer(minLength: 12)

                controls
            }

            if state.phase == .downloading {
                downloadProgress
            }

            if state.phase == .failed, let error = state.errorMessage {
                Text(error)
                    .font(.sora(10))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .settingCard()
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            LocalAIMetadataItem(text: model.runtime.displayName)
            LocalAIMetadataItem(text: "\(model.dimensions)d")
            LocalAIMetadataItem(text: model.pooling.displayName)
            LocalAIMetadataItem(text: model.parameterCount)
            LocalAIMetadataItem(text: model.recommendedTier)
            LocalAIMetadataItem(text: model.licenseName)
            LocalAIMetadataItem(text: sourceLabel)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Label("Select", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
            }
            .controlSize(.small)
            .disabled(isSelected)

            switch state.phase {
            case .installed:
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.78)
            case .notInstalled, .failed:
                Button(action: onDownload) {
                    Label(state.phase == .failed ? "Retry" : "Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
            }
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let total = state.byteCount, total > 0 {
                ProgressView(value: Double(state.bytesReceived), total: Double(total))
                    .controlSize(.small)
                Text("\(Format.bytes(state.bytesReceived)) / \(Format.bytes(total))")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text(Format.bytes(state.bytesReceived))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var sourceLabel: String {
        switch model.artifact.sourceKind {
        case .githubRelease: "GitHub"
        case .huggingFace: "Hugging Face"
        }
    }
}

private struct LocalAIMetadataItem: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.sora(10))
            .foregroundStyle(Color.stxMuted)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct LocalAIStatusPill: View {
    enum Tone {
        case accent
        case warning
        case neutral
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.sora(9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .accent: .stxAccent
        case .warning: .orange
        case .neutral: .stxMuted
        }
    }

    private var background: Color {
        switch tone {
        case .accent: Color.stxAccent.opacity(0.13)
        case .warning: Color.orange.opacity(0.12)
        case .neutral: Color.primary.opacity(0.06)
        }
    }
}

private extension Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

#if DEBUG
#Preview {
    LocalAIModelsSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 820)
}
#endif
