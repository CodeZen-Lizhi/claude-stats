import Foundation
import Testing
@testable import ClaudeStats

@Suite("AI config scanner")
struct AIConfigScannerTests {
    @Test("Discovers Codex global/project configs with missing files as coverage")
    func discoversConfigsAndDiagnostics() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let project = root.appendingPathComponent("Projects/DemoApp", isDirectory: true)

        try TempDir.write("model = \"gpt-5\"\n", to: codexHome.appendingPathComponent("config.toml"))
        try TempDir.write("# Agents\nTODO: review rules\n", to: codexHome.appendingPathComponent("AGENTS.md"))
        try TempDir.write(#"{"name":"codex-plugin"}"#, to: codexHome.appendingPathComponent("plugins/example/plugin.json"))

        try TempDir.write("# Project agents\n", to: project.appendingPathComponent("AGENTS.md"))
        try TempDir.write(#"model = "broken"#, to: project.appendingPathComponent(".codex/config.toml"))

        let snapshot = await makeScanner(codexHome: codexHome)
            .scan(sessions: [makeSession(provider: .codex, cwd: project.path)])

        let global = try #require(snapshot.projects.first { $0.id == AIConfigProject.globalID })
        #expect(global.documents.contains { $0.title == "config.toml" && $0.exists })
        #expect(global.documents.contains { $0.title == "AGENTS.md" && $0.exists })
        #expect(global.documents.contains { $0.kind == .pluginConfig && $0.title == "plugin.json" })

        let projectGroup = try #require(snapshot.projects.first { $0.path == project.path })
        #expect(projectGroup.documents.contains { $0.title == "Project AGENTS.md" && $0.exists })

        let projectConfig = try #require(projectGroup.documents.first { $0.title == "Project config.toml" })
        #expect(projectConfig.exists)
        #expect(snapshot.summary.planStats.total == 0)
    }

    @Test("Markdown stats are fence-aware and count tasks")
    func markdownStats() {
        let stats = AIConfigScanner.stats(forMarkdown: """
        # Heading
        - [ ] Open task
        - [x] Done task
        TODO: next
        blocked until review
        ```swift
        # Not a heading
        - [ ] Not a task
        ```
        cancelled item
        """)

        #expect(stats.headingCount == 1)
        #expect(stats.uncheckedTaskCount == 1)
        #expect(stats.checkedTaskCount == 1)
        #expect(stats.todoMentions == 1)
        #expect(stats.blockedMentions == 1)
        #expect(stats.cancelledMentions == 1)
    }

    @Test("Large files keep metadata and skip content preview")
    func largeFileSkipsPreview() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let project = root.appendingPathComponent("Projects/Large", isDirectory: true)
        let largeMarkdown = String(repeating: "x", count: AIConfigScanner.previewByteLimit + 1)
        try TempDir.write(largeMarkdown, to: project.appendingPathComponent("AGENTS.md"))

        let snapshot = await makeScanner(codexHome: codexHome)
            .scan(sessions: [makeSession(provider: .codex, cwd: project.path)])
        let projectGroup = try #require(snapshot.projects.first { $0.path == project.path })
        let document = try #require(projectGroup.documents.first { $0.title == "Project AGENTS.md" })

        #expect(document.exists)
        #expect(document.contentPreview == nil)
        #expect(document.isPreviewTruncated)
        #expect(document.fileSize ?? 0 > Int64(AIConfigScanner.previewByteLimit))
        #expect(document.diagnostics.contains { $0.severity == .warning })
    }

    private func makeScanner(codexHome: URL) -> AIConfigScanner {
        let registry = ProviderRegistry(
            providers: [
                CodexProvider(paths: CodexPaths(homeDirectory: codexHome), pricing: TestPricing.table),
            ]
        )
        return AIConfigScanner(registry: registry)
    }

    private func makeSession(provider: ProviderKind, cwd: String) -> Session {
        Session(
            id: "\(provider.rawValue)::test",
            externalID: "test",
            provider: provider,
            projectDirectoryName: cwd.replacingOccurrences(of: "/", with: "-"),
            filePath: "\(cwd)/session.jsonl",
            cwd: cwd,
            lastModified: Date(timeIntervalSince1970: 100),
            fileSize: 100,
            stats: nil
        )
    }
}
