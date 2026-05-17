import AppKit
import SwiftUI

struct ConfigurationsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selectedProvider: ProviderKind = .claude
    @State private var selectedScope: ConfigProfileScope = .global
    @State private var selectedProfileID: UUID?
    @State private var selectedSnapshotID: UUID?
    @State private var captureName = ""
    @State private var profilePendingApply: ConfigProfile?
    @State private var pendingSelection: ConfigurationPendingSelection?
    @State private var showDiscardDraftAlert = false
    @State private var suppressProviderDirtyCheck = false
    @State private var editor = ConfigurationEditorViewModel()

    private var vm: ConfigurationProfilesViewModel { env.configurationProfiles }
    private var screenSnapshot: ConfigurationScreenSnapshot {
        let profiles = vm.profiles(for: selectedProvider)
        let selectedProfile = selectedProfile(from: profiles)
        let selectedSnapshot = selectedSnapshot(in: selectedProfile)
        return ConfigurationScreenSnapshot(
            profiles: profiles,
            selectedProfile: selectedProfile,
            selectedSnapshot: selectedSnapshot,
            activeProfileID: vm.activeProfile(for: selectedProvider)?.id,
            scopeOptions: vm.scopeOptions(for: selectedProvider),
            statuses: vm.statuses,
            latestBackupURL: selectedProfile.flatMap { vm.latestBackupURL(for: $0) }
        )
    }

    private func selectedProfile(from profiles: [ConfigProfile]) -> ConfigProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    private func selectedSnapshot(in selectedProfile: ConfigProfile?) -> ConfigFileSnapshot? {
        guard let selectedProfile else { return nil }
        if let selectedSnapshotID,
           let snapshot = selectedProfile.files.first(where: { $0.id == selectedSnapshotID }) {
            return snapshot
        }
        return selectedProfile.files.first
    }

    var body: some View {
        let snapshot = screenSnapshot

        CenteredPaneContainer {
            VStack(alignment: .leading, spacing: 24) {
                header
                capturePanel(snapshot: snapshot)
                content(snapshot: snapshot)
            }
        }
        .task {
            selectedProvider = env.preferences.selectedProvider
            await vm.loadIfNeeded()
            await vm.refreshScopeOptions(from: env.store.sessions)
            normalizeSelection()
            normalizeSnapshotSelection()
            openSelectedSnapshot(force: true)
            resetCaptureName()
        }
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            let sessions = env.store.sessions
            Task { await vm.refreshScopeOptions(from: sessions) }
        }
        .onChange(of: selectedProvider) { oldValue, newValue in
            if suppressProviderDirtyCheck {
                suppressProviderDirtyCheck = false
                handleProviderChanged()
            } else if editor.isDirty {
                pendingSelection = .provider(newValue)
                suppressProviderDirtyCheck = true
                selectedProvider = oldValue
                showDiscardDraftAlert = true
            } else {
                handleProviderChanged()
            }
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
                        openSelectedSnapshot(force: false)
                    }
                }
            }
        }
        .alert("Configuration Error", isPresented: errorBinding) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
        .alert("Discard Unsaved Changes?", isPresented: $showDiscardDraftAlert) {
            Button("Cancel", role: .cancel) { pendingSelection = nil }
            Button("Discard", role: .destructive) { commitPendingSelection() }
        } message: {
            Text("The current editor draft has not been saved to this profile.")
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

    private func capturePanel(snapshot: ConfigurationScreenSnapshot) -> some View {
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
                    ForEach(snapshot.scopeOptions) { scope in
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

    private func content(snapshot: ConfigurationScreenSnapshot) -> some View {
        ConfigurationResponsiveLayout {
            profileList(snapshot: snapshot)
            fileList(snapshot: snapshot)
            editorDetail(snapshot: snapshot)
        }
    }

    private func profileList(snapshot: ConfigurationScreenSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Profiles")
            VStack(spacing: 0) {
                if snapshot.profiles.isEmpty {
                    emptyProfiles
                } else {
                    ForEach(snapshot.profiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            status: snapshot.status(for: profile),
                            isSelected: snapshot.selectedProfile?.id == profile.id,
                            isActive: snapshot.activeProfileID == profile.id
                        ) {
                            requestSelectProfile(profile.id)
                        }
                        if profile.id != snapshot.profiles.last?.id {
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
    private func fileList(snapshot: ConfigurationScreenSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Files")
            if let selectedProfile = snapshot.selectedProfile {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedProfile.files.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No files captured")
                                .font(.sora(13, weight: .medium))
                            Text("Capture a profile with existing config files to edit it here.")
                                .font(.sora(11))
                                .foregroundStyle(Color.stxMuted)
                        }
                        .padding(14)
                    } else {
                        ForEach(selectedProfile.files) { file in
                            ConfigFileSnapshotRow(
                                snapshot: file,
                                isSelected: snapshot.selectedSnapshot?.id == file.id
                            ) {
                                requestSelectSnapshot(file.id)
                            }
                            if file.id != selectedProfile.files.last?.id {
                                StxRule().padding(.leading, 12)
                            }
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

    private func editorDetail(snapshot: ConfigurationScreenSnapshot) -> some View {
        ConfigurationEditorPane(
            profile: snapshot.selectedProfile,
            status: snapshot.selectedProfile.map { snapshot.status(for: $0) } ?? .unknown,
            latestBackupURL: snapshot.latestBackupURL,
            isWorking: vm.isWorking,
            editor: editor,
            saveToProfile: saveEditorToProfile,
            saveToDisk: saveEditorToDisk,
            revert: revertEditorDraft,
            applyProfile: applySelectedProfile,
            duplicateProfile: duplicateSelectedProfile,
            deleteProfile: deleteSelectedProfile
        )
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
            selectedSnapshotID = profile.files.first?.id
            editor.open(profile: profile, snapshot: profile.files.first)
            resetCaptureName()
        }
    }

    private func handleProviderChanged() {
        normalizeSelection()
        selectedScope = .global
        normalizeSnapshotSelection()
        openSelectedSnapshot(force: true)
        resetCaptureName()
    }

    private func normalizeSelection() {
        let available = vm.profiles(for: selectedProvider)
        if let selectedProfileID, available.contains(where: { $0.id == selectedProfileID }) {
            return
        }
        selectedProfileID = vm.activeProfile(for: selectedProvider)?.id ?? available.first?.id
    }

    private func normalizeSnapshotSelection() {
        normalizeSnapshotSelection(in: selectedProfile(from: vm.profiles(for: selectedProvider)))
    }

    private func normalizeSnapshotSelection(in selectedProfile: ConfigProfile?) {
        guard let selectedProfile else {
            selectedSnapshotID = nil
            return
        }
        if let selectedSnapshotID,
           selectedProfile.files.contains(where: { $0.id == selectedSnapshotID }) {
            return
        }
        selectedSnapshotID = selectedProfile.files.first?.id
    }

    private func requestSelectProfile(_ profileID: UUID) {
        guard profileID != selectedProfileID else { return }
        if editor.isDirty {
            pendingSelection = .profile(profileID)
            showDiscardDraftAlert = true
        } else {
            selectProfile(profileID)
        }
    }

    private func requestSelectSnapshot(_ snapshotID: UUID) {
        guard snapshotID != selectedSnapshotID else { return }
        if editor.isDirty {
            pendingSelection = .snapshot(snapshotID)
            showDiscardDraftAlert = true
        } else {
            selectSnapshot(snapshotID)
        }
    }

    private func commitPendingSelection() {
        guard let pendingSelection else { return }
        self.pendingSelection = nil
        editor.clear()
        switch pendingSelection {
        case .provider(let provider):
            suppressProviderDirtyCheck = true
            selectedProvider = provider
        case .profile(let profileID):
            selectProfile(profileID)
        case .snapshot(let snapshotID):
            selectSnapshot(snapshotID)
        }
    }

    private func selectProfile(_ profileID: UUID) {
        selectedProfileID = profileID
        normalizeSnapshotSelection()
        openSelectedSnapshot(force: true)
    }

    private func selectSnapshot(_ snapshotID: UUID) {
        selectedSnapshotID = snapshotID
        openSelectedSnapshot(force: true)
    }

    private func openSelectedSnapshot(force: Bool = false) {
        normalizeSnapshotSelection()
        let selectedProfile = selectedProfile(from: vm.profiles(for: selectedProvider))
        let selectedSnapshot = selectedSnapshot(in: selectedProfile)
        guard let selectedProfile else {
            editor.clear()
            return
        }
        if force {
            editor.open(profile: selectedProfile, snapshot: selectedSnapshot)
        } else {
            editor.syncIfClean(profile: selectedProfile, snapshot: selectedSnapshot)
        }
    }

    private func saveEditorToProfile() {
        guard let profileID = editor.profileID,
              let snapshotID = editor.snapshotID else { return }
        editor.setWorking(true)
        Task {
            let updatedProfile = await vm.saveSnapshotToProfile(
                profileID: profileID,
                snapshotID: snapshotID,
                content: editor.draftContent
            )
            editor.setWorking(false)
            syncEditorAfterSave(updatedProfile: updatedProfile, snapshotID: snapshotID)
        }
    }

    private func saveEditorToDisk() {
        guard let profileID = editor.profileID,
              let snapshotID = editor.snapshotID else { return }
        editor.setWorking(true)
        Task {
            let result = await vm.saveSnapshotToDisk(
                profileID: profileID,
                snapshotID: snapshotID,
                content: editor.draftContent
            )
            editor.setWorking(false)
            if let result {
                syncEditorAfterSave(updatedProfile: result.updatedProfile, snapshotID: snapshotID, savedAt: result.savedAt)
            }
        }
    }

    private func syncEditorAfterSave(updatedProfile: ConfigProfile?, snapshotID: UUID, savedAt: Date = .now) {
        guard let updatedProfile,
              let snapshot = updatedProfile.files.first(where: { $0.id == snapshotID }) else { return }
        selectedProfileID = updatedProfile.id
        selectedSnapshotID = snapshot.id
        editor.markSaved(profile: updatedProfile, snapshot: snapshot, savedAt: savedAt)
    }

    private func revertEditorDraft() {
        let snapshot = screenSnapshot
        guard let selectedProfile = snapshot.selectedProfile else { return }
        editor.revert(profile: selectedProfile, snapshot: snapshot.selectedSnapshot)
    }

    private func applySelectedProfile() {
        guard let selectedProfile = screenSnapshot.selectedProfile else { return }
        profilePendingApply = selectedProfile
    }

    private func duplicateSelectedProfile() {
        guard let selectedProfile = screenSnapshot.selectedProfile else { return }
        Task {
            if let copy = await vm.duplicate(selectedProfile) {
                selectedProfileID = copy.id
                selectedSnapshotID = copy.files.first?.id
                editor.open(profile: copy, snapshot: copy.files.first)
            }
        }
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile = screenSnapshot.selectedProfile else { return }
        Task {
            await vm.delete(selectedProfile)
            normalizeSelection()
            normalizeSnapshotSelection()
            openSelectedSnapshot(force: true)
        }
    }

    private func resetCaptureName() {
        captureName = vm.defaultProfileName(provider: selectedProvider, scope: selectedScope)
    }
}

private struct ConfigurationScreenSnapshot {
    let profiles: [ConfigProfile]
    let selectedProfile: ConfigProfile?
    let selectedSnapshot: ConfigFileSnapshot?
    let activeProfileID: UUID?
    let scopeOptions: [ConfigProfileScope]
    let statuses: [UUID: ConfigProfileStatus]
    let latestBackupURL: URL?

    func status(for profile: ConfigProfile) -> ConfigProfileStatus {
        statuses[profile.id] ?? .unknown
    }
}

private struct ConfigurationResponsiveLayout: Layout {
    private let profileWidth: CGFloat = 270
    private let filesWidth: CGFloat = 300
    private let editorMinWidth: CGFloat = 360
    private let spacing: CGFloat = 18

    private var horizontalBreakpoint: CGFloat {
        profileWidth + filesWidth + editorMinWidth + spacing * 2
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? horizontalBreakpoint
        guard subviews.count == 3, proposedWidth >= horizontalBreakpoint else {
            return verticalSizeThatFits(proposal: proposal, subviews: subviews)
        }

        let sizes = horizontalSizes(width: proposedWidth, subviews: subviews)
        return CGSize(width: proposedWidth, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3, bounds.width >= horizontalBreakpoint else {
            placeVertically(in: bounds, subviews: subviews)
            return
        }

        let editorWidth = bounds.width - profileWidth - filesWidth - spacing * 2
        var x = bounds.minX
        subviews[0].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: profileWidth, height: nil)
        )
        x += profileWidth + spacing
        subviews[1].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: filesWidth, height: nil)
        )
        x += filesWidth + spacing
        subviews[2].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: editorWidth, height: nil)
        )
    }

    private func horizontalSizes(width: CGFloat, subviews: Subviews) -> [CGSize] {
        let editorWidth = width - profileWidth - filesWidth - spacing * 2
        return [
            subviews[0].sizeThatFits(ProposedViewSize(width: profileWidth, height: nil)),
            subviews[1].sizeThatFits(ProposedViewSize(width: filesWidth, height: nil)),
            subviews[2].sizeThatFits(ProposedViewSize(width: editorWidth, height: nil)),
        ]
    }

    private func verticalSizeThatFits(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        let sizes = subviews.map { subview in
            subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        }
        let totalHeight = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(
            width: proposal.width ?? (sizes.map(\.width).max() ?? 0),
            height: totalHeight
        )
    }

    private func placeVertically(in bounds: CGRect, subviews: Subviews) {
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
            y += size.height + spacing
        }
    }
}

private enum ConfigurationPendingSelection: Equatable {
    case provider(ProviderKind)
    case profile(UUID)
    case snapshot(UUID)
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
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: select) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: snapshot.path)])
            } label: {
                Image(systemName: "finder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .frame(width: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
            } else if hovering {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
            }
        }
        .padding(4)
        .onHover { hovering = $0 }
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
