import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("Configuration profiles view model")
struct ConfigurationProfilesViewModelTests {
    @Test("Project scope options are cached by provider with stable unique cwd order")
    func scopeOptionsAreCachedByProvider() async {
        let vm = makeViewModel()
        let sessions = [
            makeSession("claude-a", provider: .claude, cwd: "/work/alpha"),
            makeSession("codex-a", provider: .codex, cwd: "/work/codex"),
            makeSession("claude-duplicate", provider: .claude, cwd: "/work/alpha"),
            makeSession("claude-empty", provider: .claude, cwd: ""),
            makeSession("claude-b", provider: .claude, cwd: "/work/beta"),
        ]

        await vm.refreshScopeOptions(from: sessions)

        #expect(vm.scopeOptions(for: .claude) == [
            .global,
            .project(path: "/work/alpha"),
            .project(path: "/work/beta"),
        ])
        #expect(vm.scopeOptions(for: .codex) == [
            .global,
            .project(path: "/work/codex"),
        ])
        #expect(vm.scopeOptions(for: .gemini) == [.global])
    }

    @Test("Loading the library rebuilds sorted profile and active-profile caches")
    func reloadRebuildsProfileCaches() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigurationProfileStore(rootDirectory: temp.appendingPathComponent("Profiles", isDirectory: true))
        let older = makeProfile(provider: .claude, name: "Older", updatedAt: Date(timeIntervalSince1970: 10))
        let newer = makeProfile(provider: .claude, name: "Newer", updatedAt: Date(timeIntervalSince1970: 20))
        let codex = makeProfile(provider: .codex, name: "Codex", updatedAt: Date(timeIntervalSince1970: 15))
        try await store.saveLibrary(ConfigurationProfileLibrary(
            profiles: [older, codex, newer],
            activeProfileIDsByProvider: [.claude: older.id, .codex: codex.id]
        ))

        let vm = makeViewModel(store: store)
        await vm.reload()

        #expect(vm.profiles(for: .claude).map(\.id) == [newer.id, older.id])
        #expect(vm.profiles(for: .codex).map(\.id) == [codex.id])
        #expect(vm.activeProfile(for: .claude)?.id == older.id)
        #expect(vm.activeProfile(for: .codex)?.id == codex.id)
    }

    @Test("Profile caches stay in sync after capture, duplicate, save, and delete")
    func mutationOperationsRefreshProfileCaches() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("ClaudeConfig", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeConfig, withIntermediateDirectories: true)
        let settingsURL = claudeConfig.appendingPathComponent("settings.json", isDirectory: false)
        try #"{"theme":"dark"}"#.write(to: settingsURL, atomically: true, encoding: .utf8)

        let store = ConfigurationProfileStore(rootDirectory: temp.appendingPathComponent("Profiles", isDirectory: true))
        let registry = ProviderRegistry(pricing: TestPricing.table, claudePaths: ClaudePaths(configDirectory: claudeConfig))
        let vm = ConfigurationProfilesViewModel(store: store, registry: registry)

        await vm.reload()
        let capturedResult = await vm.captureCurrent(name: "Captured", provider: .claude, scope: .global)
        let captured = try #require(capturedResult)
        #expect(vm.profiles(for: .claude).map(\.id) == [captured.id])
        #expect(vm.activeProfile(for: .claude)?.id == captured.id)

        let copyResult = await vm.duplicate(captured)
        let copy = try #require(copyResult)
        #expect(vm.profiles(for: .claude).contains { $0.id == copy.id })

        let snapshotID = try #require(copy.files.first?.id)
        let updatedResult = await vm.saveSnapshotToProfile(
            profileID: copy.id,
            snapshotID: snapshotID,
            content: #"{"theme":"light"}"#
        )
        let updated = try #require(updatedResult)
        #expect(vm.profiles(for: .claude).first { $0.id == copy.id }?.files.first?.content == #"{"theme":"light"}"#)

        await vm.delete(updated)
        #expect(vm.profiles(for: .claude).contains { $0.id == copy.id } == false)
        #expect(vm.profiles(for: .claude).contains { $0.id == captured.id })
    }

    private func makeViewModel(
        store: ConfigurationProfileStore = ConfigurationProfileStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ConfigurationProfilesViewModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    ) -> ConfigurationProfilesViewModel {
        ConfigurationProfilesViewModel(store: store, registry: ProviderRegistry(pricing: TestPricing.table))
    }

    private func makeSession(_ id: String, provider: ProviderKind, cwd: String?) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: provider,
            projectDirectoryName: id,
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: Date(timeIntervalSince1970: 1),
            fileSize: 1
        )
    }

    private func makeProfile(provider: ProviderKind, name: String, updatedAt: Date) -> ConfigProfile {
        ConfigProfile(
            provider: provider,
            scope: .global,
            name: name,
            files: [
                ConfigFileSnapshot(
                    title: "\(name).json",
                    path: "/tmp/\(name).json",
                    fileKind: .json,
                    content: "{}",
                    contentHash: ConfigurationProfileStore.hash("{}"),
                    capturedAt: updatedAt
                ),
            ],
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
