import Foundation
import Observation

@MainActor
@Observable
final class ConfigurationEditorViewModel {
    private(set) var profileID: UUID?
    private(set) var snapshotID: UUID?
    private(set) var title = ""
    private(set) var path = ""
    private(set) var fileKind: ProviderConfigFileKind = .text
    private(set) var draftContent = ""
    private(set) var diagnostics: [ConfigurationEditorDiagnostic] = []
    private(set) var isWorking = false
    private(set) var lastSavedAt: Date?
    private(set) var cursorLine = 1
    private(set) var cursorColumn = 1

    @ObservationIgnored private let service: ConfigurationEditorService
    @ObservationIgnored private var savedContentHash = ConfigurationProfileStore.hash("")
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?

    init(service: ConfigurationEditorService = ConfigurationEditorService()) {
        self.service = service
    }

    var isOpen: Bool {
        profileID != nil && snapshotID != nil
    }

    var isDirty: Bool {
        ConfigurationProfileStore.hash(draftContent) != savedContentHash
    }

    var hasDiagnostics: Bool {
        !diagnostics.isEmpty
    }

    var primaryDiagnostic: ConfigurationEditorDiagnostic? {
        diagnostics.first
    }

    func open(profile: ConfigProfile, snapshot: ConfigFileSnapshot?) {
        diagnosticsTask?.cancel()

        guard let snapshot else {
            clear()
            return
        }

        profileID = profile.id
        snapshotID = snapshot.id
        title = snapshot.title
        path = snapshot.path
        fileKind = snapshot.fileKind
        draftContent = snapshot.content
        savedContentHash = snapshot.contentHash
        diagnostics = ConfigurationEditorService.diagnosticsSync(for: snapshot.content, kind: snapshot.fileKind)
        cursorLine = 1
        cursorColumn = 1
    }

    func syncIfClean(profile: ConfigProfile, snapshot: ConfigFileSnapshot?) {
        guard !isDirty else { return }
        open(profile: profile, snapshot: snapshot)
    }

    func clear() {
        diagnosticsTask?.cancel()
        profileID = nil
        snapshotID = nil
        title = ""
        path = ""
        fileKind = .text
        draftContent = ""
        savedContentHash = ConfigurationProfileStore.hash("")
        diagnostics = []
        cursorLine = 1
        cursorColumn = 1
        lastSavedAt = nil
    }

    func updateDraft(_ content: String) {
        guard draftContent != content else { return }
        draftContent = content
        scheduleDiagnostics()
    }

    func revert(profile: ConfigProfile, snapshot: ConfigFileSnapshot?) {
        open(profile: profile, snapshot: snapshot)
    }

    func markSaved(profile: ConfigProfile, snapshot: ConfigFileSnapshot, savedAt: Date = .now) {
        open(profile: profile, snapshot: snapshot)
        lastSavedAt = savedAt
    }

    func updateCursor(line: Int, column: Int) {
        cursorLine = max(1, line)
        cursorColumn = max(1, column)
    }

    func setWorking(_ working: Bool) {
        isWorking = working
    }

    private func scheduleDiagnostics() {
        diagnosticsTask?.cancel()
        let content = draftContent
        let kind = fileKind
        diagnosticsTask = Task { [weak self, service] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let updated = await service.diagnostics(for: content, kind: kind)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.diagnostics = updated
            }
        }
    }
}
