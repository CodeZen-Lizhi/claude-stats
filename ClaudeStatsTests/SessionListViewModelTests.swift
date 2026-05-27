import Foundation
import Testing
@testable import ClaudeStats

@Suite("SessionListViewModel")
@MainActor
struct SessionListViewModelTests {
    @Test("Project groups expose real project folder URLs")
    func projectGroupsExposeProjectFolderURLs() throws {
        let project = try TempDir.make()
        let agent = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: project)
            try? FileManager.default.removeItem(at: agent)
        }
        let store = SessionStore(registry: ProviderRegistry(providers: []), pricing: TestPricing.table)
        store.loadPreviewSessions([
            Self.session(id: "codex::project", projectDirectoryName: project.path, cwd: project.path, sourceKind: .project),
            Self.session(id: "codex::agent", projectDirectoryName: "codex::agent-sessions", cwd: agent.path, sourceKind: .agent),
        ])

        let groups = SessionListViewModel().projectGroups(from: store, provider: .codex, costMode: .standardAPI)
        let projectGroup = try #require(groups.first { $0.id == project.path })
        let agentGroup = try #require(groups.first { $0.id == "codex::agent-sessions" })

        #expect(projectGroup.projectFolderURL?.standardizedFileURL.path == project.standardizedFileURL.path)
        #expect(agentGroup.projectFolderURL == nil)
    }

    private static func session(
        id: String,
        projectDirectoryName: String,
        cwd: String,
        sourceKind: SessionSourceKind
    ) -> Session {
        Session(
            id: id,
            externalID: id.replacingOccurrences(of: "codex::", with: ""),
            provider: .codex,
            projectDirectoryName: projectDirectoryName,
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            sourceKind: sourceKind,
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 1,
            stats: SessionStats(
                title: id,
                messageCount: 1,
                firstActivity: Date(timeIntervalSince1970: 1_000),
                lastActivity: Date(timeIntervalSince1970: 1_000),
                models: [],
                timeline: []
            )
        )
    }
}
