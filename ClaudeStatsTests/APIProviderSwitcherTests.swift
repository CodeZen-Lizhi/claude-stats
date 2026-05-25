import Foundation
import Testing
@testable import ClaudeStats

@Suite("API provider switcher")
struct APIProviderSwitcherTests {
    @Test("Codex provider writes auth and config while preserving common config")
    func codexProviderPreservesCommonConfig() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(#"{"OPENAI_API_KEY":"old-key"}"#, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            model_provider = "old"
            model = "old-model"

            [model_providers.old]
            name = "Old"
            base_url = "https://old.example"

            [mcp_servers.github]
            command = "gh"
            args = ["mcp", "server"]
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let provider = CLIAPIProvider(
            id: "openrouter",
            cli: .codex,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: .inline("sk-new"),
            model: "openai/gpt-oss"
        )

        _ = try await store.apply(provider: provider, currentActive: nil, keyStorageMode: .json)

        let auth = try readJSONObject(codexHome.appendingPathComponent("auth.json"))
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(auth["OPENAI_API_KEY"] as? String == "sk-new")
        #expect(config.contains(#"model_provider = "openrouter""#))
        #expect(config.contains(#"model = "openai/gpt-oss""#))
        #expect(config.contains("[model_providers.openrouter]"))
        #expect(config.contains(#"base_url = "https://openrouter.ai/api/v1""#))
        #expect(config.contains("[mcp_servers.github]"))
        #expect(config.contains(#"command = "gh""#))
        #expect(config.contains("[model_providers.old]") == false)
    }

    @Test("Import Current creates Default Codex provider")
    func importCurrentCreatesDefaultProvider() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(#"{"OPENAI_API_KEY":"sk-current"}"#, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            model_provider = "current"
            model = "current-model"

            [model_providers.current]
            name = "Current"
            base_url = "https://current.example"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let provider = try await store.importCurrentProvider(
            cli: .codex,
            name: "Default",
            id: "default",
            keyStorageMode: .json
        )

        #expect(provider.id == "default")
        #expect(provider.origin.kind == .importedDefault)
        #expect(provider.name == "Default")
        #expect(provider.baseURL == "https://current.example")
        #expect(provider.apiKey == .inline("sk-current"))
        #expect(provider.model == "current-model")
    }

    @MainActor
    @Test("Enable Provider backs up live files and updates active id")
    func enableProviderBacksUpAndUpdatesActiveID() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(#"{"OPENAI_API_KEY":"old-key"}"#, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(#"model = "old-model""#, to: codexHome.appendingPathComponent("config.toml"))
        let store = makeStore(temp: temp, codexHome: codexHome)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        await vm.addProvider(keyStorageMode: .json)
        vm.draftName = "Gateway"
        vm.draftBaseURL = "https://gateway.example"
        vm.draftAPIKey = "sk-gateway"
        vm.draftModel = "gateway-model"

        await vm.enableSelectedProvider(rawMode: false, keyStorageMode: .json)

        let active = try #require(vm.activeProvider(for: .codex))
        #expect(active.name == "Gateway")
        #expect(vm.latestApplyResult != nil)
        if let backup = vm.latestApplyResult?.backupDirectory {
            #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path))
        }
        let auth = try readJSONObject(codexHome.appendingPathComponent("auth.json"))
        #expect(auth["OPENAI_API_KEY"] as? String == "sk-gateway")
    }

    @Test("Universal provider generates Codex child provider")
    func universalProviderGeneratesCodexChild() throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let (universal, initialChildren) = store.makeUniversalProvider(keyStorageMode: .json)
        #expect(initialChildren.map(\.cli) == [.codex])

        let saved = try store.universalBySavingDraft(
            existing: universal,
            editedCLI: .codex,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-universal",
            model: "openai/gpt-oss",
            keyStorageMode: .json
        )
        let child = try #require(store.childProviders(for: saved, keyStorageMode: .json).first)
        #expect(child.cli == .codex)
        #expect(child.name == "OpenRouter")
        #expect(child.baseURL == "https://openrouter.ai/api/v1")
        #expect(child.model == "openai/gpt-oss")
        #expect(child.apiKey == .inline("sk-universal"))
    }

    @Test("JSON and Keychain API key storage resolve the same key")
    func apiKeyStorageModesResolveKeys() throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        let store = makeStore(temp: temp, secretStore: secretStore)
        let existing = CLIAPIProvider(id: "provider", cli: .codex, name: "Provider")

        let jsonProvider = try store.providerBySavingDraft(
            existing: existing,
            name: "Provider",
            category: .custom,
            baseURL: "https://json.example",
            apiKey: "sk-json",
            model: "json-model",
            rawConfig: "",
            rawMode: false,
            keyStorageMode: .json
        )
        let keychainProvider = try store.providerBySavingDraft(
            existing: existing,
            name: "Provider",
            category: .custom,
            baseURL: "https://keychain.example",
            apiKey: "sk-keychain",
            model: "keychain-model",
            rawConfig: "",
            rawMode: false,
            keyStorageMode: .keychain
        )

        #expect(jsonProvider.apiKey == .inline("sk-json"))
        if case .keychain(let account) = keychainProvider.apiKey {
            #expect(secretStore.readAPIKey(account: account) == "sk-keychain")
        } else {
            Issue.record("Expected keychain provider secret")
        }
        #expect(store.resolvedAPIKey(for: jsonProvider.apiKey) == "sk-json")
        #expect(store.resolvedAPIKey(for: keychainProvider.apiKey) == "sk-keychain")
    }

    @MainActor
    @Test("Deleting a Keychain provider removes its stored key")
    func deletingKeychainProviderRemovesStoredKey() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-old", account: "codex-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let provider = CLIAPIProvider(
            id: "provider",
            cli: .codex,
            origin: .appSpecific,
            name: "Provider",
            apiKey: .keychain(account: "codex-provider")
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(cliProviders: [provider]))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        let loadedProvider = try #require(vm.providers(for: .codex).first { $0.id == "provider" })
        vm.selectProvider(loadedProvider, keyStorageMode: .keychain)

        await vm.deleteSelectedProvider(keyStorageMode: .keychain)

        #expect(secretStore.readAPIKey(account: "codex-provider") == nil)
        #expect(vm.providers(for: .codex).contains { $0.id == "provider" } == false)
    }

    @MainActor
    @Test("Provider list cache invalidates after library mutation")
    func providerListCacheInvalidatesAfterMutation() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        let initial = vm.providers(for: .codex)
        #expect(vm.providers(for: .codex).map(\.id) == initial.map(\.id))

        await vm.addProvider(keyStorageMode: .json)

        let selectedID = try #require(vm.selectedProviderID)
        let updated = vm.providers(for: .codex)
        #expect(updated.count == initial.count + 1)
        #expect(updated.contains { $0.id == selectedID })
    }

    @MainActor
    @Test("Switching a provider away from Keychain removes the old stored key")
    func switchingProviderAwayFromKeychainRemovesOldStoredKey() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-old", account: "codex-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let provider = CLIAPIProvider(
            id: "provider",
            cli: .codex,
            origin: .appSpecific,
            name: "Provider",
            apiKey: .keychain(account: "codex-provider")
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(cliProviders: [provider]))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        let loadedProvider = try #require(vm.providers(for: .codex).first { $0.id == "provider" })
        vm.selectProvider(loadedProvider, keyStorageMode: .keychain)
        vm.draftAPIKey = "sk-json"

        let saved = await vm.saveDraft(rawMode: false, keyStorageMode: .json)

        let updatedProvider = try #require(vm.providers(for: .codex).first { $0.id == "provider" })
        #expect(saved)
        #expect(updatedProvider.apiKey == .inline("sk-json"))
        #expect(secretStore.readAPIKey(account: "codex-provider") == nil)
    }

    @Test("Provider library persists CLI-keyed maps as string dictionaries")
    func providerLibraryPersistsCLIMaps() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let universal = UniversalAPIProvider(
            id: "u",
            name: "Universal",
            modelOverrides: [.codex: "codex-model"]
        )
        let library = ConfigurationProviderLibrary(
            universalProviders: [universal],
            activeProviderIDs: [.codex: "official"],
            commonConfigByCLI: [.codex: "[mcp_servers.github]"]
        )

        try await store.saveLibrary(library)

        let raw = try String(
            contentsOf: temp
                .appendingPathComponent("ProviderLibrary", isDirectory: true)
                .appendingPathComponent("providers.json", isDirectory: false),
            encoding: .utf8
        )
        #expect(raw.contains(#""codex" : "official""#))
        #expect(raw.contains(#""codex" : "codex-model""#))

        let loaded = try await store.loadLibrary()
        #expect(loaded.activeProviderIDs[.codex] == "official")
        #expect(loaded.universalProviders.first?.modelOverrides[.codex] == "codex-model")
    }

    @Test("Legacy non-Codex providers are ignored when loading library")
    func legacyNonCodexProvidersAreIgnored() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let libraryURL = temp
            .appendingPathComponent("ProviderLibrary", isDirectory: true)
            .appendingPathComponent("providers.json", isDirectory: false)
        try TempDir.write(
            """
            {
              "cliProviders" : [
                { "id" : "legacy", "cli" : "claude", "origin" : { "kind" : "appSpecific" }, "name" : "Legacy", "category" : "custom", "baseURL" : "", "apiKey" : { "kind" : "none" }, "model" : "", "rawConfig" : "", "createdAt" : "2026-01-01T00:00:00Z", "updatedAt" : "2026-01-01T00:00:00Z" },
                { "id" : "codex", "cli" : "codex", "origin" : { "kind" : "appSpecific" }, "name" : "Codex", "category" : "custom", "baseURL" : "", "apiKey" : { "kind" : "none" }, "model" : "", "rawConfig" : "", "createdAt" : "2026-01-01T00:00:00Z", "updatedAt" : "2026-01-01T00:00:00Z" }
              ],
              "universalProviders" : [],
              "activeProviderIDs" : { "claude" : "legacy", "codex" : "codex" },
              "commonConfigByCLI" : { "claude" : "old", "codex" : "new" }
            }
            """,
            to: libraryURL
        )

        let loaded = try await makeStore(temp: temp).loadLibrary()

        #expect(loaded.cliProviders.map(\.id) == ["codex"])
        #expect(loaded.activeProviderIDs == [.codex: "codex"])
        #expect(loaded.commonConfigByCLI == [.codex: "new"])
    }

    private func makeStore(
        temp: URL,
        codexHome: URL? = nil,
        secretStore: any APIProviderSecretStoring = InMemoryAPIProviderSecretStore()
    ) -> ConfigurationProviderStore {
        ConfigurationProviderStore(
            rootDirectory: temp.appendingPathComponent("ProviderLibrary", isDirectory: true),
            codexPaths: CodexPaths(homeDirectory: codexHome ?? temp.appendingPathComponent("Codex", isDirectory: true)),
            secretStore: secretStore
        )
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
