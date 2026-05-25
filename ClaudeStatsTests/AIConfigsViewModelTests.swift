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

        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let alpha = root.appendingPathComponent("Projects/Alpha", isDirectory: true)
        let beta = root.appendingPathComponent("Projects/Beta", isDirectory: true)

        try TempDir.write("# Alpha Agents\n", to: alpha.appendingPathComponent("AGENTS.md"))
        try TempDir.write("# Global\n", to: codexHome.appendingPathComponent("AGENTS.md"))
        try TempDir.write("model = \"gpt-5\"\n", to: codexHome.appendingPathComponent("config.toml"))
        try TempDir.write(#"{"name":"fixture"}"#, to: codexHome.appendingPathComponent("plugins/fixture/plugin.json"))
        try TempDir.write(#"model = "broken"#, to: alpha.appendingPathComponent(".codex/config.toml"))

        let vm = AIConfigsViewModel(scanner: makeScanner(codexHome: codexHome))
        let sessions = [
            makeSession(provider: .codex, cwd: alpha.path),
            makeSession(provider: .codex, cwd: beta.path),
        ]

        await vm.loadIfNeeded(sessions: sessions)

        let alphaProjects = vm.filteredProjects(filter: .all, query: "alpha")
        #expect(alphaProjects.map(\.name) == ["Alpha"])

        let providerProjects = vm.filteredProjects(filter: .provider, query: "")
        #expect(providerProjects.map(\.name) == ["Global", "Alpha"])

        #expect(vm.count(for: .instructions) == 3)
        #expect(vm.count(for: .provider) == 2)
        #expect(vm.count(for: .plans) == 0)
        #expect(vm.count(for: .plugins) == 1)

        let alphaID = try #require(alphaProjects.first?.id)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "alpha") == alphaID)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "beta") != alphaID)

        let alphaProviderProject = try #require(providerProjects.first { $0.name == "Alpha" })
        let providerID = try #require(vm.documents(in: alphaProviderProject, filter: .provider, query: "").first?.id)
        #expect(vm.resolvedDocumentID(current: providerID, projectID: alphaID, filter: .provider, query: "") == providerID)
        #expect(vm.resolvedDocumentID(current: nil, projectID: alphaID, section: .provider, query: "") == providerID)

        await vm.reload(sessions: sessions)
        #expect(vm.resolvedProjectID(current: alphaID, filter: .all, query: "alpha") == alphaID)
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
