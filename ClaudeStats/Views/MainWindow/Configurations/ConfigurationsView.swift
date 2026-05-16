import AppKit
import SwiftUI

struct ConfigurationsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selectedProvider: ProviderKind = .claude
    @State private var selectedScope: ConfigProfileScope = .global
    @State private var selectedProfileID: UUID?
    @State private var captureName = ""
    @State private var profilePendingApply: ConfigProfile?

    private var vm: ConfigurationProfilesViewModel { env.configurationProfiles }
    private var profiles: [ConfigProfile] { vm.profiles(for: selectedProvider) }
    private var selectedProfile: ConfigProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }
    private var scopeOptions: [ConfigProfileScope] {
        vm.scopeOptions(for: selectedProvider, sessions: env.store.sessions)
    }

    var body: some View {
        CenteredPaneContainer {
            VStack(alignment: .leading, spacing: 24) {
                header
                capturePanel
                content
            }
        }
        .task {
            selectedProvider = env.preferences.selectedProvider
            await vm.loadIfNeeded()
            normalizeSelection()
            resetCaptureName()
        }
        .onChange(of: selectedProvider) { _, _ in
            normalizeSelection()
            selectedScope = .global
            resetCaptureName()
        }
        .onChange(of: selectedScope) { _, _ in resetCaptureName() }
        .sheet(item: $profilePendingApply) { profile in
            ApplyConfigurationSheet(profile: profile, backupURL: vm.latestBackupURL(for: profile)) {
                profilePendingApply = nil
            } apply: {
                Task {
                    let ok = await vm.apply(profile)
                    if ok {
                        selectedProfileID = profile.id
                        profilePendingApply = nil
                    }
                }
            }
        }
        .alert("Configuration Error", isPresented: errorBinding) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configurations")
                    .font(.sora(28, weight: .semibold))
                Text("Capture and switch AI CLI configuration profiles with automatic backups.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            Picker("", selection: $selectedProvider) {
                ForEach(env.preferences.orderedEnabledProviders) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture Current")
                        .font(.sora(15, weight: .semibold))
                    Text("Save the files currently on disk as a reusable profile.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await captureCurrent() }
                } label: {
                    Label("Capture", systemImage: "plus")
                }
                .disabled(vm.isWorking)
            }

            HStack(spacing: 10) {
                TextField("Profile name", text: $captureName)
                    .textFieldStyle(.roundedBorder)
                    .font(.sora(12))
                Picker("", selection: $selectedScope) {
                    ForEach(scopeOptions) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
        }
        .padding(14)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
    }

    private var content: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                profileList
                    .frame(width: 310)
                profileDetail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: 18) {
                profileList
                profileDetail
            }
        }
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Profiles")
            VStack(spacing: 0) {
                if profiles.isEmpty {
                    emptyProfiles
                } else {
                    ForEach(profiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            status: vm.status(for: profile),
                            isSelected: selectedProfile?.id == profile.id,
                            isActive: vm.activeProfile(for: selectedProvider)?.id == profile.id
                        ) {
                            selectedProfileID = profile.id
                        }
                        if profile.id != profiles.last?.id {
                            StxRule().padding(.leading, 12)
                        }
                    }
                }
            }
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var profileDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Files")
            if let selectedProfile {
                VStack(alignment: .leading, spacing: 0) {
                    profileActions(selectedProfile)
                    StxRule()
                    ForEach(selectedProfile.files) { snapshot in
                        ConfigFileSnapshotRow(snapshot: snapshot)
                        if snapshot.id != selectedProfile.files.last?.id {
                            StxRule().padding(.leading, 12)
                        }
                    }
                }
                .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No profile selected")
                        .font(.sora(13, weight: .medium))
                    Text("Capture the current configuration to start switching profiles.")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
            }
        }
    }

    private func profileActions(_ profile: ConfigProfile) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.sora(15, weight: .semibold))
                Text("\(profile.scope.displayName) • \(profile.files.count) files")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            Button("Apply") { profilePendingApply = profile }
                .disabled(vm.isWorking)
            Button("Duplicate") {
                Task {
                    if let copy = await vm.duplicate(profile) {
                        selectedProfileID = copy.id
                    }
                }
            }
            .disabled(vm.isWorking)
            Button("Delete", role: .destructive) {
                Task {
                    await vm.delete(profile)
                    normalizeSelection()
                }
            }
            .disabled(vm.isWorking)
            if let backupURL = vm.latestBackupURL(for: profile) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .help("Reveal Backup")
            }
        }
        .padding(14)
    }

    private var emptyProfiles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No profiles")
                .font(.sora(13, weight: .medium))
            Text("Capture the current \(selectedProvider.shortName) configuration.")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.sora(15, weight: .semibold))
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { vm.lastError != nil },
            set: { newValue in
                if !newValue { vm.clearError() }
            }
        )
    }

    private func captureCurrent() async {
        let name = captureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? vm.defaultProfileName(provider: selectedProvider, scope: selectedScope)
            : captureName
        if let profile = await vm.captureCurrent(name: name, provider: selectedProvider, scope: selectedScope) {
            selectedProfileID = profile.id
            resetCaptureName()
        }
    }

    private func normalizeSelection() {
        let available = profiles
        if let selectedProfileID, available.contains(where: { $0.id == selectedProfileID }) {
            return
        }
        selectedProfileID = vm.activeProfile(for: selectedProvider)?.id ?? available.first?.id
    }

    private func resetCaptureName() {
        captureName = vm.defaultProfileName(provider: selectedProvider, scope: selectedScope)
    }
}

private struct ProfileListRow: View {
    let profile: ConfigProfile
    let status: ConfigProfileStatus
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(profile.provider.monochromeAssetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .clipped()
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    Text(profile.name)
                        .font(.sora(12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isActive {
                        Circle()
                            .fill(Color.stxAccent)
                            .frame(width: 7, height: 7)
                            .help("Active")
                    }
                }
                HStack(spacing: 8) {
                    Text(profile.scope.displayName)
                    Text("\(profile.files.count) files")
                    Spacer(minLength: 6)
                    ProfileStatusBadge(status: status)
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .onHover { hovering = $0 }
    }
}

private struct ConfigFileSnapshotRow: View {
    let snapshot: ConfigFileSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.sora(12, weight: .medium))
                Text(snapshot.path)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Text(snapshot.fileKind.displayName)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: snapshot.path)])
            } label: {
                Image(systemName: "finder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var iconName: String {
        switch snapshot.fileKind {
        case .json:
            "curlybraces"
        case .markdown:
            "doc.text"
        case .toml:
            "slider.horizontal.3"
        case .text:
            "doc.plaintext"
        }
    }
}

private struct ProfileStatusBadge: View {
    let status: ConfigProfileStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .lineLimit(1)
        }
    }

    private var color: Color {
        switch status {
        case .clean:
            Color.stxAccent
        case .modified:
            Color(red: 0.92, green: 0.58, blue: 0.16)
        case .missing:
            Color(red: 0.85, green: 0.22, blue: 0.18)
        case .empty, .unknown:
            Color.stxMuted
        }
    }
}

private struct ApplyConfigurationSheet: View {
    let profile: ConfigProfile
    let backupURL: URL?
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apply Profile")
                .font(.sora(20, weight: .semibold))
            Text("This will overwrite \(profile.files.count) configuration files. Claude Stats will create a timestamped backup before writing anything.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let backupURL {
                Text("Last backup: \(backupURL.path)")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

#if DEBUG
#Preview("Configurations") {
    ConfigurationsView()
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 700)
}
#endif
