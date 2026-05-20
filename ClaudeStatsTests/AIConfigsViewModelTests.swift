import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("AI configs view model")
struct AIConfigsViewModelTests {
    @Test("Filters, searches, and preserves valid selections")
    func filteringAndSelection() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeHome = root.appendingPathComponent(".claude", isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let alpha = root.appendingPathComponent("Projects/Alpha", isDirectory: true)
        let beta = root.appendingPathComponent("Projects/Beta", isDirectory: true)

        try TempDir.write("# Alpha Agents\n", to: alpha.appendingPathComponent("AGENTS.md"))
        try TempDir.write("# Beta Claude\n", to: beta.appendingPathComponent("CLAUDE.md"))
        try TempDir.write("Project path: \(alpha.path)\n- [ ] Alpha plan\n", to: claudeHome.appendingPathComponent("plans/alpha.md"))
        try TempDir.write("# Global\n", to: claudeHome.appendingPathComponent("CLAUDE.md"))
        try TempDir.write("model = \"gpt-5\"\n", to: codexHome.appendingPathComponent("config.toml"))
        try TempDir.write(#"{"name":"fixture"}"#, to: codexHome.appendingPathComponent("plugins/fixture/plugin.json"))
        try TempDir.write(#"{"broken": true"#, to: alpha.appendingPathComponent(".claude/settings.local.json"))

        let vm = AIConfigsViewModel(scanner: makeScanner(claudeHome: claudeHome, codexHome: codexHome))
        let sessions = [
            makeSession(provider: .codex, cwd: alpha.path),
            makeSession(provider: .claude, cwd: beta.path),
        ]

        await vm.loadIfNeeded(sessions: sessions)

        let alphaProjects = vm.filteredProjects(filter: .all, query: "alpha")
        #expect(alphaProjects.map(\.name) == ["Alpha"])

        let planProjects = vm.filteredProjects(filter: .plans, query: "")
        #expect(planProjects.map(\.name) == ["Alpha"])

        #expect(vm.count(for: .instructions) == 6)
        #expect(vm.count(for: .provider) == 3)
        #expect(vm.count(for: .plans) == 1)
        #expect(vm.count(for: .plugins) == 1)
        #expect(vm.count(for: .diagnostics) == 1)

        let diagnosticProjects = vm.filteredProjects(section: .diagnostics, query: "settings.local")
        #expect(diagnosticProjects.map(\.name) == ["Alpha"])

        let alphaID = try #require(alphaProjects.first?.id)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "alpha") == alphaID)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "beta") != alphaID)
        #expect(vm.resolvedProjectID(current: alphaID, section: .diagnostics, query: "settings.local") == alphaID)

        let planID = try #require(vm.documents(in: planProjects.first, filter: .plans, query: "").first?.id)
        #expect(vm.resolvedDocumentID(current: planID, projectID: alphaID, filter: .plans, query: "") == planID)
        #expect(vm.resolvedDocumentID(current: nil, projectID: alphaID, section: .plans, query: "") == planID)

        await vm.reload(sessions: sessions)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "alpha") == alphaID)
    }

    private func makeScanner(claudeHome: URL, codexHome: URL) -> AIConfigScanner {
        let registry = ProviderRegistry(
            providers: [
                ClaudeProvider(paths: ClaudePaths(configDirectory: claudeHome), pricing: TestPricing.table),
                CodexProvider(paths: CodexPaths(homeDirectory: codexHome), pricing: TestPricing.table),
            ]
        )
        return AIConfigScanner(registry: registry)
    }

    private func makeSession(provider: ProviderKind, cwd: String) -> Session {
        Session(
            id: "\(provider.rawValue)::\(cwd)",
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
