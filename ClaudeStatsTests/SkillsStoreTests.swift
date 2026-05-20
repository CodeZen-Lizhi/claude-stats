import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("Skills store")
struct SkillsStoreTests {
    @Test("Loads local skills, filters groups, and preserves valid selection")
    func localFilteringAndSelection() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        try TempDir.write(
            """
            ---
            name: Alpha Skill
            description: Helps alpha projects
            ---
            """,
            to: root.appendingPathComponent(".codex/skills/alpha/SKILL.md")
        )
        try TempDir.write(
            """
            ---
            name: Beta Skill
            description: Helps beta projects
            ---
            """,
            to: root.appendingPathComponent(".claude/skills/beta/SKILL.md")
        )

        let store = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: FakeSkillsShClient(),
            credentials: InMemorySkillsShCredentialStore()
        )

        await store.loadIfNeeded(sessions: [])
        #expect(store.snapshot.summary.groupCount == 2)
        #expect(store.selectedLocalGroup?.name == "Alpha Skill")

        store.searchText = "beta"
        store.syncLocalSelection()
        #expect(store.filteredLocalGroups.map(\.name) == ["Beta Skill"])
        #expect(store.visibleLocalRows.map(\.name) == ["Beta Skill"])
        #expect(store.visibleLocalRows.first?.providerBadges == ["Claude"])
        #expect(store.selectedLocalGroup?.name == "Beta Skill")

        store.selectedProviderID = "codex"
        store.searchText = ""
        store.syncLocalSelection()
        #expect(store.filteredLocalGroups.map(\.name) == ["Alpha Skill"])
        #expect(store.groupsByID[store.selectedLocalGroupID ?? ""]?.name == "Alpha Skill")
    }

    @Test("Remote search uses saved API key, caches detail, and reports install state")
    func remoteSearchAndDetail() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let localSkill = root.appendingPathComponent(".codex/skills/react-native", isDirectory: true)
        try TempDir.write(
            """
            ---
            name: React Native
            description: Local copy
            ---
            """,
            to: localSkill.appendingPathComponent("SKILL.md")
        )

        let fakeClient = FakeSkillsShClient()
        fakeClient.searchResults = [
            RemoteSkillSummary(
                id: "expo/skills/react-native",
                slug: "react-native",
                name: "React Native",
                source: "expo/skills",
                installs: 100,
                installURL: "https://github.com/expo/skills",
                url: "https://skills.sh/expo/skills/react-native"
            ),
        ]
        fakeClient.details["expo/skills/react-native"] = RemoteSkillDetail.testValue(
            id: "expo/skills/react-native",
            hash: "remote-hash"
        )
        fakeClient.audits["expo/skills/react-native"] = SkillsShAuditReport(
            id: "expo/skills/react-native",
            source: "expo/skills",
            slug: "react-native",
            audits: [
                SkillsShAuditEntry(
                    provider: "Socket",
                    slug: "socket",
                    status: "pass",
                    summary: "No alerts",
                    auditedAt: nil,
                    riskLevel: "LOW",
                    categories: []
                ),
            ]
        )

        let credentials = InMemorySkillsShCredentialStore(apiKey: "sk_test")
        let store = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: fakeClient,
            credentials: credentials
        )

        await store.loadIfNeeded(sessions: [])
        store.selectedTab = .discover
        store.searchText = "react"
        await store.searchOrLoadTrending()

        let remote = try #require(store.remoteResults.first)
        #expect(remote.id == "expo/skills/react-native")
        #expect(store.installState(for: remote) == .possiblyInstalled)
        #expect(store.discoverRows.first?.installState == .possiblyInstalled)

        store.selectRemoteSkill(remote)
        await store.loadRemoteDetail(id: remote.id)

        #expect(store.remoteDetails[remote.id]?.detail?.hash == "remote-hash")
        #expect(store.remoteDetails[remote.id]?.audit?.audits.first?.provider == "Socket")
        #expect(store.remoteDetails[remote.id]?.skillMarkdown?.contains("React Native") == true)
        #expect(store.remoteDetails[remote.id]?.fileEntries.first?.path == "SKILL.md")
        #expect(store.installState(for: remote) == .outOfDate)
        #expect(store.discoverRows.first?.installState == .outOfDate)
    }

    @Test("Curated rows cache remote lookup and selected skill")
    func curatedRowsCacheRemoteLookup() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let remote = RemoteSkillSummary(
            id: "owner/repo/skill",
            slug: "skill",
            name: "Skill",
            source: "owner/repo",
            installs: 42
        )
        let fakeClient = FakeSkillsShClient()
        fakeClient.curatedOwners = [
            SkillsShCuratedOwner(
                owner: "owner",
                totalInstalls: 42,
                featuredRepo: nil,
                featuredSkill: nil,
                skills: [remote]
            ),
        ]
        let store = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: fakeClient,
            credentials: InMemorySkillsShCredentialStore(apiKey: "sk_test")
        )

        store.selectedTab = .curated
        await store.loadCurated()

        #expect(store.curatedOwnerRows.first?.owner == "owner")
        #expect(store.curatedOwnerRows.first?.skills.first?.skill.id == remote.id)
        store.selectRemoteSkill(remote)
        #expect(store.selectedRemoteSkill?.id == remote.id)
    }

    @Test("Remote operations use cached API key after startup")
    func remoteOperationsUseCachedAPIKey() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let credentials = OneShotSkillsShCredentialStore(apiKey: "sk_cached")
        let fakeClient = FakeSkillsShClient()
        fakeClient.leaderboardResults = [
            RemoteSkillSummary(id: "owner/repo/skill", slug: "skill", name: "Skill"),
        ]
        let store = SkillsStore(
            scanner: SkillsLocalScanner(homeDirectory: root),
            client: fakeClient,
            credentials: credentials
        )

        store.selectedTab = .discover
        await store.searchOrLoadTrending()

        #expect(store.remoteResults.first?.id == "owner/repo/skill")
        #expect(credentials.readCount == 1)
    }
}

final class FakeSkillsShClient: SkillsShClienting, @unchecked Sendable {
    var leaderboardResults: [RemoteSkillSummary] = []
    var searchResults: [RemoteSkillSummary] = []
    var curatedOwners: [SkillsShCuratedOwner] = []
    var details: [String: RemoteSkillDetail] = [:]
    var audits: [String: SkillsShAuditReport] = [:]

    func leaderboard(apiKey: String, view: String, limit: Int) async throws -> [RemoteSkillSummary] {
        leaderboardResults
    }

    func search(query: String, apiKey: String, limit: Int) async throws -> [RemoteSkillSummary] {
        searchResults
    }

    func curated(apiKey: String) async throws -> [SkillsShCuratedOwner] {
        curatedOwners
    }

    func detail(id: String, apiKey: String) async throws -> RemoteSkillDetail {
        guard let detail = details[id] else { throw SkillsShClient.ClientError.notFound }
        return detail
    }

    func audit(id: String, apiKey: String) async throws -> SkillsShAuditReport? {
        audits[id]
    }
}

final class OneShotSkillsShCredentialStore: SkillsShCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private(set) var readCount = 0

    init(apiKey: String) {
        value = apiKey
    }

    func readAPIKey() -> String? {
        lock.withLock {
            readCount += 1
            defer { value = nil }
            return value
        }
    }

    func saveAPIKey(_ apiKey: String) {
        lock.withLock { value = apiKey }
    }

    func deleteAPIKey() {
        lock.withLock { value = nil }
    }
}

private extension RemoteSkillDetail {
    static func testValue(id: String, hash: String?) -> RemoteSkillDetail {
        let data = Data(
            """
            {
              "id": "\(id)",
              "source": "expo/skills",
              "slug": "react-native",
              "installs": 10,
              "hash": \(hash.map { "\"\($0)\"" } ?? "null"),
              "files": [
                { "path": "SKILL.md", "contents": "---\\nname: React Native\\n---\\n" }
              ]
            }
            """.utf8
        )
        return try! JSONDecoder().decode(RemoteSkillDetail.self, from: data)
    }
}
