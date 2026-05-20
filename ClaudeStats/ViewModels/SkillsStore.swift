import Foundation
import Observation

@MainActor
@Observable
final class SkillsStore {
    var selectedTab: SkillsWorkspaceTab = .installed
    var selectedDetailTab: SkillsDetailTab = .overview
    var localSearchText = "" {
        didSet { rebuildLocalDerivedState() }
    }
    var discoverSearchText = ""
    var curatedSearchText = "" {
        didSet {
            rebuildRemoteDerivedState()
            selectedRemoteSkillID = resolvedRemoteID(current: selectedRemoteSkillID)
        }
    }
    var searchText: String {
        get {
            switch selectedTab {
            case .installed: localSearchText
            case .discover: discoverSearchText
            case .curated: curatedSearchText
            }
        }
        set {
            switch selectedTab {
            case .installed:
                localSearchText = newValue
            case .discover:
                discoverSearchText = newValue
            case .curated:
                curatedSearchText = newValue
            }
        }
    }
    var selectedProviderID: String? {
        didSet { rebuildLocalDerivedState() }
    }
    var scopeFilter: SkillScopeFilter = .all {
        didSet { rebuildLocalDerivedState() }
    }
    var selectedLocalGroupID: String? {
        didSet { rebuildSelectedLocalDetailState() }
    }
    var selectedRemoteSkillID: String? {
        didSet { rebuildSelectedRemoteDetailState() }
    }
    var apiKeyDraft = ""

    private(set) var snapshot: SkillsSnapshot = .empty {
        didSet {
            rebuildInstalledIndex()
            rebuildHeaderSummaryText()
            rebuildLocalDerivedState()
            rebuildRemoteDerivedState()
        }
    }
    private(set) var isScanning = false
    private(set) var isRemoteLoading = false {
        didSet { rebuildSelectedRemoteDetailState() }
    }
    private(set) var lastError: String?
    private(set) var remoteError: String?
    private(set) var hasAPIKey = false
    private(set) var remoteResults: [RemoteSkillSummary] = [] {
        didSet { rebuildRemoteDerivedState() }
    }
    private(set) var curatedOwners: [SkillsShCuratedOwner] = [] {
        didSet { rebuildRemoteDerivedState() }
    }
    private(set) var remoteDetails: [String: SkillRemoteDetailBundle] = [:] {
        didSet {
            rebuildRemoteDerivedState()
            rebuildSelectedRemoteDetailState()
        }
    }
    private(set) var headerSummaryText = ""
    private(set) var visibleLocalGroups: [LocalSkillGroup] = []
    private(set) var visibleLocalRows: [LocalSkillRowModel] = []
    private(set) var groupsByID: [String: LocalSkillGroup] = [:]
    private(set) var discoverRows: [RemoteSkillRowModel] = []
    private(set) var curatedOwnerRows: [CuratedSkillOwnerRowModel] = []
    private(set) var remoteSkillsByID: [String: RemoteSkillSummary] = [:]
    private(set) var selectedLocalDetailModel: LocalSkillDetailModel?
    private(set) var selectedRemoteDetailModel: RemoteSkillDetailModel?

    @ObservationIgnored private let scanner: SkillsLocalScanner
    @ObservationIgnored private let client: any SkillsShClienting
    @ObservationIgnored private let credentials: any SkillsShCredentialStoring
    @ObservationIgnored private var hasLoadedLocal = false
    @ObservationIgnored private var cachedAPIKey: String?
    @ObservationIgnored private var lastProjectRootSignature: String?
    @ObservationIgnored private var installedHashes: Set<String> = []
    @ObservationIgnored private var localGroupIDs: Set<String> = []

    init(
        scanner: SkillsLocalScanner = SkillsLocalScanner(),
        client: any SkillsShClienting = SkillsShClient(),
        credentials: any SkillsShCredentialStoring = SkillsShKeychainStore.shared
    ) {
        self.scanner = scanner
        self.client = client
        self.credentials = credentials
        let key = credentials.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedAPIKey = key?.isEmpty == false ? key : nil
        hasAPIKey = cachedAPIKey != nil
        rebuildHeaderSummaryText()
    }

    var filteredLocalGroups: [LocalSkillGroup] {
        visibleLocalGroups
    }

    var selectedLocalGroup: LocalSkillGroup? {
        guard let selectedLocalGroupID else { return nil }
        return groupsByID[selectedLocalGroupID]
    }

    var remoteDisplayResults: [RemoteSkillSummary] {
        switch selectedTab {
        case .installed:
            []
        case .discover:
            discoverRows.map(\.skill)
        case .curated:
            curatedOwnerRows.flatMap { owner in owner.skills.map(\.skill) }
        }
    }

    var selectedRemoteSkill: RemoteSkillSummary? {
        guard let selectedRemoteSkillID else { return nil }
        return remoteSkillsByID[selectedRemoteSkillID]
    }

    var selectedLocalDetail: LocalSkillDetailModel? {
        selectedLocalDetailModel
    }

    var selectedRemoteDetail: RemoteSkillDetailModel? {
        selectedRemoteDetailModel
    }

    func loadIfNeeded(sessions: [Session]) async {
        guard !hasLoadedLocal else { return }
        await reloadLocal(sessions: sessions)
    }

    func reloadLocal(sessions: [Session]) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        lastProjectRootSignature = projectRootSignature(sessions)
        snapshot = await scanner.scan(sessions: sessions)
        hasLoadedLocal = true
        lastError = nil
    }

    func reloadLocalIfProjectRootsChanged(sessions: [Session]) async {
        let signature = projectRootSignature(sessions)
        guard signature != lastProjectRootSignature else { return }
        await reloadLocal(sessions: sessions)
    }

    func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try credentials.saveAPIKey(trimmed)
            cachedAPIKey = trimmed
            hasAPIKey = true
            apiKeyDraft = ""
            remoteError = nil
        } catch {
            remoteError = "Could not save skills.sh API key: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        credentials.deleteAPIKey()
        cachedAPIKey = nil
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
            let query = discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func selectLocalGroup(id: String) {
        selectedLocalGroupID = id
        selectedDetailTab = .overview
    }

    func selectLocalGroup(_ group: LocalSkillGroup) {
        selectLocalGroup(id: group.id)
    }

    func selectRemoteSkill(_ skill: RemoteSkillSummary) {
        selectedRemoteSkillID = skill.id
        selectedDetailTab = .overview
    }

    func installState(for remote: RemoteSkillSummary) -> SkillInstallState {
        computedInstallState(for: remote)
    }

    func syncLocalSelection() {
        let groups = visibleLocalGroups
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
        guard let key = cachedAPIKey, !key.isEmpty else {
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

    private func rebuildLocalDerivedState() {
        groupsByID = Dictionary(uniqueKeysWithValues: snapshot.groups.map { ($0.id, $0) })
        let normalizedQuery = normalized(localSearchText)
        visibleLocalGroups = snapshot.groups.filter { group in
            let providerMatches = selectedProviderID.map { providerID in
                group.skills.contains { $0.providerID == providerID }
            } ?? true
            guard providerMatches else { return false }
            guard group.skills.contains(where: { scopeFilter.matches($0.scope) }) else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return matches(group: group, query: normalizedQuery)
        }
        visibleLocalRows = visibleLocalGroups.map(LocalSkillRowModel.init(group:))
        syncLocalSelection()
        rebuildSelectedLocalDetailState()
    }

    private func rebuildInstalledIndex() {
        installedHashes = Set(snapshot.skills.compactMap(\.contentHash))
        localGroupIDs = Set(snapshot.groups.map(\.id))
    }

    private func rebuildRemoteDerivedState() {
        discoverRows = remoteResults.map { skill in
            RemoteSkillRowModel(skill: skill, installState: computedInstallState(for: skill))
        }
        let curatedQuery = normalized(curatedSearchText)
        curatedOwnerRows = curatedOwners.compactMap { owner in
            let skills = owner.skills
                .filter { skill in
                    guard !curatedQuery.isEmpty else { return true }
                    return remoteMatches(skill: skill, owner: owner.owner, query: curatedQuery)
                }
                .map { skill in
                    RemoteSkillRowModel(skill: skill, installState: computedInstallState(for: skill))
                }
            guard !skills.isEmpty || curatedQuery.isEmpty && owner.skills.isEmpty else { return nil }
            CuratedSkillOwnerRowModel(
                owner: owner.owner,
                totalInstalls: owner.totalInstalls,
                skills: skills
            )
        }

        var nextRemoteSkillsByID: [String: RemoteSkillSummary] = [:]
        for row in discoverRows {
            nextRemoteSkillsByID[row.skill.id] = row.skill
        }
        for owner in curatedOwnerRows {
            for row in owner.skills {
                nextRemoteSkillsByID[row.skill.id] = row.skill
            }
        }
        remoteSkillsByID = nextRemoteSkillsByID
        rebuildSelectedRemoteDetailState()
    }

    private func rebuildHeaderSummaryText() {
        var items = [
            "\(snapshot.summary.groupCount) skills",
            "\(snapshot.summary.skillCount) copies",
            "\(snapshot.summary.providerCount) providers",
        ]
        if snapshot.summary.pluginSkillCount > 0 {
            items.append("\(snapshot.summary.pluginSkillCount) plugin skills")
        }
        if snapshot.summary.projectRootCount > 0 {
            items.append("\(snapshot.summary.projectRootCount) projects")
        }
        if let scannedAt = snapshot.scannedAt {
            items.append("Updated \(Format.relativeDate(scannedAt))")
        }
        headerSummaryText = items.joined(separator: " . ")
    }

    private func rebuildSelectedLocalDetailState() {
        guard let selectedLocalGroup else {
            selectedLocalDetailModel = nil
            return
        }
        selectedLocalDetailModel = LocalSkillDetailModel(group: selectedLocalGroup)
    }

    private func rebuildSelectedRemoteDetailState() {
        guard let skill = selectedRemoteSkill else {
            selectedRemoteDetailModel = nil
            return
        }
        selectedRemoteDetailModel = RemoteSkillDetailModel(
            skill: skill,
            bundle: remoteDetails[skill.id],
            installState: computedInstallState(for: skill),
            isDetailLoading: isRemoteLoading
        )
    }

    private func remoteMatches(skill: RemoteSkillSummary, owner: String, query: String) -> Bool {
        if owner.lowercased().contains(query) { return true }
        if skill.id.lowercased().contains(query) { return true }
        if skill.name.lowercased().contains(query) { return true }
        if skill.slug?.lowercased().contains(query) == true { return true }
        if skill.source?.lowercased().contains(query) == true { return true }
        if skill.sourceType?.lowercased().contains(query) == true { return true }
        return false
    }

    private func computedInstallState(for remote: RemoteSkillSummary) -> SkillInstallState {
        let bundle = remoteDetails[remote.id]
        if let hash = bundle?.detail?.hash, installedHashes.contains(hash) {
            return .installed
        }

        let candidates = [
            remote.slug,
            remote.name,
            remote.id.split(separator: "/").last.map(String.init),
        ]
        .compactMap { $0 }
        .map(LocalSkillItem.normalizedName)

        let nameMatches = candidates.contains { localGroupIDs.contains($0) }
        if nameMatches, bundle?.detail?.hash != nil {
            return .outOfDate
        }
        if nameMatches {
            return .possiblyInstalled
        }
        return .notInstalled
    }

    private func projectRootSignature(_ sessions: [Session]) -> String {
        let roots = Set(
            sessions
                .compactMap(\.cwd)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
        )
        return roots.sorted().joined(separator: "\n")
    }

    private func errorDescription(_ error: Error) -> String {
        if let error = error as? SkillsShClient.ClientError {
            return error.description
        }
        return error.localizedDescription
    }
}
