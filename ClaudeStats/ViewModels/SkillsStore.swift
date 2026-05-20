import Foundation
import Observation

@MainActor
@Observable
final class SkillsStore {
    var selectedTab: SkillsWorkspaceTab = .installed
    var selectedDetailTab: SkillsDetailTab = .overview
    var searchText = ""
    var selectedProviderID: String?
    var scopeFilter: SkillScopeFilter = .all
    var selectedLocalGroupID: String?
    var selectedRemoteSkillID: String?
    var apiKeyDraft = ""

    private(set) var snapshot: SkillsSnapshot = .empty
    private(set) var isScanning = false
    private(set) var isRemoteLoading = false
    private(set) var lastError: String?
    private(set) var remoteError: String?
    private(set) var hasAPIKey = false
    private(set) var remoteResults: [RemoteSkillSummary] = []
    private(set) var curatedOwners: [SkillsShCuratedOwner] = []
    private(set) var remoteDetails: [String: SkillRemoteDetailBundle] = [:]

    @ObservationIgnored private let scanner: SkillsLocalScanner
    @ObservationIgnored private let client: any SkillsShClienting
    @ObservationIgnored private let credentials: any SkillsShCredentialStoring
    @ObservationIgnored private var hasLoadedLocal = false

    init(
        scanner: SkillsLocalScanner = SkillsLocalScanner(),
        client: any SkillsShClienting = SkillsShClient(),
        credentials: any SkillsShCredentialStoring = SkillsShKeychainStore.shared
    ) {
        self.scanner = scanner
        self.client = client
        self.credentials = credentials
        let key = credentials.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        hasAPIKey = key?.isEmpty == false
    }

    var filteredLocalGroups: [LocalSkillGroup] {
        let normalizedQuery = normalized(searchText)
        return snapshot.groups.filter { group in
            let providerMatches = selectedProviderID.map { providerID in
                group.skills.contains { $0.providerID == providerID }
            } ?? true
            guard providerMatches else { return false }
            guard group.skills.contains(where: { scopeFilter.matches($0.scope) }) else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return matches(group: group, query: normalizedQuery)
        }
    }

    var selectedLocalGroup: LocalSkillGroup? {
        guard let selectedLocalGroupID else { return nil }
        return filteredLocalGroups.first { $0.id == selectedLocalGroupID }
            ?? snapshot.groups.first { $0.id == selectedLocalGroupID }
    }

    var remoteDisplayResults: [RemoteSkillSummary] {
        switch selectedTab {
        case .installed:
            []
        case .discover:
            remoteResults
        case .curated:
            curatedOwners.flatMap(\.skills)
        }
    }

    var selectedRemoteSkill: RemoteSkillSummary? {
        guard let selectedRemoteSkillID else { return nil }
        return remoteDisplayResults.first { $0.id == selectedRemoteSkillID }
    }

    func loadIfNeeded(sessions: [Session]) async {
        guard !hasLoadedLocal else { return }
        await reloadLocal(sessions: sessions)
    }

    func reloadLocal(sessions: [Session]) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        snapshot = await scanner.scan(sessions: sessions)
        hasLoadedLocal = true
        lastError = nil
        syncLocalSelection()
    }

    func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try credentials.saveAPIKey(trimmed)
            hasAPIKey = true
            apiKeyDraft = ""
            remoteError = nil
        } catch {
            remoteError = "Could not save skills.sh API key: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        credentials.deleteAPIKey()
        hasAPIKey = false
        apiKeyDraft = ""
        remoteResults = []
        curatedOwners = []
        remoteDetails = [:]
        remoteError = nil
        selectedRemoteSkillID = nil
    }

    func refreshRemote() async {
        switch selectedTab {
        case .installed:
            return
        case .discover:
            await searchOrLoadTrending()
        case .curated:
            await loadCurated()
        }
    }

    func searchOrLoadTrending() async {
        guard let apiKey = apiKey() else { return }
        guard !isRemoteLoading else { return }
        isRemoteLoading = true
        defer { isRemoteLoading = false }

        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.count >= 2 {
                remoteResults = try await client.search(query: query, apiKey: apiKey, limit: 75)
            } else {
                remoteResults = try await client.leaderboard(apiKey: apiKey, view: "trending", limit: 100)
            }
            selectedRemoteSkillID = resolvedRemoteID(current: selectedRemoteSkillID)
            remoteError = nil
        } catch {
            remoteError = errorDescription(error)
        }
    }

    func loadCurated() async {
        guard let apiKey = apiKey() else { return }
        guard !isRemoteLoading else { return }
        isRemoteLoading = true
        defer { isRemoteLoading = false }

        do {
            curatedOwners = try await client.curated(apiKey: apiKey)
            selectedRemoteSkillID = resolvedRemoteID(current: selectedRemoteSkillID)
            remoteError = nil
        } catch {
            remoteError = errorDescription(error)
        }
    }

    func loadRemoteDetail(id: String) async {
        guard remoteDetails[id]?.detail == nil || remoteDetails[id]?.audit == nil else { return }
        guard let apiKey = apiKey() else { return }

        do {
            async let detail = client.detail(id: id, apiKey: apiKey)
            async let audit = client.audit(id: id, apiKey: apiKey)
            remoteDetails[id] = SkillRemoteDetailBundle(
                detail: try await detail,
                audit: try await audit
            )
            remoteError = nil
        } catch {
            remoteError = errorDescription(error)
        }
    }

    func selectLocalGroup(_ group: LocalSkillGroup) {
        selectedLocalGroupID = group.id
        selectedDetailTab = .overview
    }

    func selectRemoteSkill(_ skill: RemoteSkillSummary) {
        selectedRemoteSkillID = skill.id
        selectedDetailTab = .overview
    }

    func installState(for remote: RemoteSkillSummary) -> SkillInstallState {
        let bundle = remoteDetails[remote.id]
        if let hash = bundle?.detail?.hash,
           snapshot.skills.contains(where: { $0.contentHash == hash }) {
            return .installed
        }

        let candidates = [
            remote.slug,
            remote.name,
            remote.id.split(separator: "/").last.map(String.init),
        ]
        .compactMap { $0 }
        .map(LocalSkillItem.normalizedName)

        let nameMatches = snapshot.groups.contains { group in
            candidates.contains(group.id)
        }

        if nameMatches, bundle?.detail?.hash != nil {
            return .outOfDate
        }
        if nameMatches {
            return .possiblyInstalled
        }
        return .notInstalled
    }

    func syncLocalSelection() {
        let groups = filteredLocalGroups
        if let selectedLocalGroupID, groups.contains(where: { $0.id == selectedLocalGroupID }) {
            return
        }
        selectedLocalGroupID = groups.first?.id
    }

    private func resolvedRemoteID(current: String?) -> String? {
        let results = remoteDisplayResults
        if let current, results.contains(where: { $0.id == current }) {
            return current
        }
        return results.first?.id
    }

    private func apiKey() -> String? {
        guard let key = credentials.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            hasAPIKey = false
            remoteError = SkillsShClient.ClientError.missingAPIKey.description
            return nil
        }
        hasAPIKey = true
        return key
    }

    private func matches(group: LocalSkillGroup, query: String) -> Bool {
        if group.name.lowercased().contains(query) { return true }
        if group.description?.lowercased().contains(query) == true { return true }
        return group.skills.contains { skill in
            skill.providerName.lowercased().contains(query)
                || skill.folderPath.lowercased().contains(query)
                || skill.plugin?.displayName.lowercased().contains(query) == true
                || skill.frontmatter.creator?.lowercased().contains(query) == true
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func errorDescription(_ error: Error) -> String {
        if let error = error as? SkillsShClient.ClientError {
            return error.description
        }
        return error.localizedDescription
    }
}
