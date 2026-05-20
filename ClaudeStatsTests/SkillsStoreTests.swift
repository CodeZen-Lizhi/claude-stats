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
        #expect(store.selectedLocalGroup?.name == "Beta Skill")

        store.selectedProviderID = "codex"
        store.searchText = ""
        store.syncLocalSelection()
        #expect(store.filteredLocalGroups.map(\.name) == ["Alpha Skill"])
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

        store.selectRemoteSkill(remote)
        await store.loadRemoteDetail(id: remote.id)

        #expect(store.remoteDetails[remote.id]?.detail?.hash == "remote-hash")
        #expect(store.remoteDetails[remote.id]?.audit?.audits.first?.provider == "Socket")
        #expect(store.installState(for: remote) == .outOfDate)
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
