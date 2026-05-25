import Foundation

enum ConfigurationProviderStoreError: LocalizedError, Sendable {
    case unsupportedCLI
    case invalidCodexConfig
    case providerNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedCLI:
            "Only Codex is supported in this switcher."
        case .invalidCodexConfig:
            "Codex provider raw config must be valid provider TOML text."
        case .providerNotFound:
            "The selected API provider could not be found."
        }
    }
}

struct ConfigurationProviderApplyResult: Sendable, Hashable {
    let backupDirectory: URL
    let appliedAt: Date
}

struct ConfigurationProviderStore: Sendable {
    let rootDirectory: URL
    let codexPaths: CodexPaths
    let secretStore: any APIProviderSecretStoring

    private var libraryURL: URL {
        rootDirectory.appendingPathComponent("providers.json", isDirectory: false)
    }

    private var backupsDirectory: URL {
        rootDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    private var codexAuthURL: URL {
        codexPaths.homeDirectory.appendingPathComponent("auth.json", isDirectory: false)
    }

    private var codexConfigURL: URL {
        codexPaths.homeDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        codexPaths: CodexPaths = .default,
        secretStore: any APIProviderSecretStoring = APIProviderKeychainStore.shared
    ) {
        self.rootDirectory = rootDirectory
        self.codexPaths = codexPaths
        self.secretStore = secretStore
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("APIProviders", isDirectory: true)
    }

    func loadLibrary() async throws -> ConfigurationProviderLibrary {
        let url = libraryURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ConfigurationProviderLibrary()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.apiProviderDecoder.decode(ConfigurationProviderLibrary.self, from: data)
        }.value
    }

    func saveLibrary(_ library: ConfigurationProviderLibrary) async throws {
        let rootDirectory = rootDirectory
        let url = libraryURL
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.apiProviderEncoder.encode(library)
            try data.write(to: url, options: .atomic)
        }.value
    }

    func deleteStoredSecrets(_ secrets: [APIProviderSecret], retainedIn library: ConfigurationProviderLibrary) {
        let retainedAccounts = Self.keychainAccounts(in: library)
        let accounts = Set(secrets.compactMap(\.keychainAccount))
        for account in accounts where !retainedAccounts.contains(account) {
            secretStore.deleteAPIKey(account: account)
        }
    }

    func ensureSystemProviders(
        in library: ConfigurationProviderLibrary,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> ConfigurationProviderLibrary {
        var updated = library
        for cli in APIProviderCLI.allCases {
            if !updated.cliProviders.contains(where: { $0.cli == cli && $0.id == "official" }) {
                updated.cliProviders.append(Self.officialProvider(for: cli))
            }
            if !updated.cliProviders.contains(where: { $0.cli == cli && $0.id == "default" }) {
                if let imported = try? await importCurrentProvider(cli: cli, name: "Default", id: "default", keyStorageMode: keyStorageMode) {
                    updated.cliProviders.append(imported)
                    updated.activeProviderIDs[cli] = imported.id
                }
            }
        }
        return updated
    }

    func importCurrentProvider(
        cli _: APIProviderCLI,
        name: String,
        id: String = UUID().uuidString,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> CLIAPIProvider {
        let live = try await readCodexLive()
        return try providerFromCodexRaw(
            id: id,
            name: name,
            origin: .importedDefault,
            category: .imported,
            rawConfig: live.config,
            authJSON: live.auth,
            keyStorageMode: keyStorageMode,
            createdAt: .now
        )
    }

    func providerBySavingDraft(
        existing: CLIAPIProvider,
        name: String,
        category: APIProviderCategory,
        baseURL: String,
        apiKey: String,
        model: String,
        rawConfig: String,
        rawMode: Bool,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> CLIAPIProvider {
        let savedAt = Date()
        if rawMode {
            var provider = try providerFromCodexRaw(
                id: existing.id,
                name: name,
                origin: existing.origin,
                category: category,
                rawConfig: rawConfig,
                authJSON: ["OPENAI_API_KEY": apiKey],
                keyStorageMode: keyStorageMode,
                createdAt: existing.createdAt,
                updatedAt: savedAt
            )
            provider.iconName = existing.iconName
            provider.iconColorHex = existing.iconColorHex
            return provider
        }

        var provider = existing
        provider.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.category = category
        provider.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.apiKey = try storedSecret(rawKey: apiKey, cli: existing.cli, providerID: existing.id, keyStorageMode: keyStorageMode)
        provider.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        provider.updatedAt = savedAt
        return provider
    }

    func makeCustomProvider(cli: APIProviderCLI, keyStorageMode: APIProviderKeyStorageMode) -> CLIAPIProvider {
        let id = UUID().uuidString
        var provider = CLIAPIProvider(
            id: id,
            cli: cli,
            origin: .appSpecific,
            name: "New Provider",
            category: .custom,
            baseURL: "",
            apiKey: .none,
            model: defaultModel(for: cli),
            iconName: cli.providerKind.monochromeAssetName
        )
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        return provider
    }

    func makeUniversalProvider(keyStorageMode: APIProviderKeyStorageMode) -> (UniversalAPIProvider, [CLIAPIProvider]) {
        let universal = UniversalAPIProvider(
            name: "Universal Provider",
            baseURL: "",
            apiKey: .none,
            modelOverrides: [.codex: defaultModel(for: .codex)],
            iconName: "network"
        )
        return (universal, childProviders(for: universal, keyStorageMode: keyStorageMode))
    }

    func universalBySavingDraft(
        existing: UniversalAPIProvider,
        editedCLI: APIProviderCLI,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> UniversalAPIProvider {
        var provider = existing
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.name = trimmedName.isEmpty ? existing.name : trimmedName
        provider.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.apiKey = try storedSecret(
            rawKey: apiKey,
            cli: editedCLI,
            providerID: existing.id,
            keyStorageMode: keyStorageMode
        )
        provider.modelOverrides[editedCLI] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.updatedAt = .now
        return provider
    }

    func childProviders(for universal: UniversalAPIProvider, keyStorageMode: APIProviderKeyStorageMode) -> [CLIAPIProvider] {
        APIProviderCLI.allCases.compactMap { cli in
            guard universal.enabledCLIs.contains(cli) else { return nil }
            let id = Self.universalChildID(universalID: universal.id, cli: cli)
            var provider = CLIAPIProvider(
                id: id,
                cli: cli,
                origin: .universal(universal.id),
                name: universal.name,
                category: .universal,
                baseURL: universal.baseURL,
                apiKey: universal.apiKey,
                model: universal.modelOverrides[cli] ?? defaultModel(for: cli),
                iconName: universal.iconName,
                iconColorHex: universal.iconColorHex,
                createdAt: universal.createdAt,
                updatedAt: universal.updatedAt
            )
            provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
            return provider
        }
    }

    func apply(
        provider: CLIAPIProvider,
        currentActive: CLIAPIProvider?,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> (ConfigurationProviderApplyResult, CLIAPIProvider?) {
        let backfilled: CLIAPIProvider?
        if let currentActive, currentActive.id != provider.id {
            backfilled = try await backfilledProvider(currentActive, keyStorageMode: keyStorageMode)
        } else {
            backfilled = nil
        }

        let backupDirectory = try await backupLiveFiles(for: provider.cli, providerID: provider.id)
        try await writeLiveConfig(for: provider)
        return (
            ConfigurationProviderApplyResult(backupDirectory: backupDirectory, appliedAt: .now),
            backfilled
        )
    }

    func resolvedAPIKey(for secret: APIProviderSecret) -> String {
        switch secret {
        case .none:
            return ""
        case .inline(let value):
            return value
        case .keychain(let account):
            return secretStore.readAPIKey(account: account) ?? ""
        }
    }

    func renderRawConfig(for provider: CLIAPIProvider) -> String {
        renderCodexConfig(provider: provider)
    }

    static func officialProvider(for cli: APIProviderCLI) -> CLIAPIProvider {
        var provider = CLIAPIProvider(
            id: "official",
            cli: cli,
            origin: .official,
            name: "OpenAI Official",
            category: .official,
            baseURL: "",
            apiKey: .none,
            model: "",
            iconName: "openai",
            iconColorHex: "#00A67E"
        )
        provider.rawConfig = ""
        return provider
    }

    static func universalChildID(universalID: String, cli: APIProviderCLI) -> String {
        "universal-\(cli.rawValue)-\(universalID)"
    }

    private static func keychainAccounts(in library: ConfigurationProviderLibrary) -> Set<String> {
        var accounts = Set<String>()
        for provider in library.cliProviders {
            if let account = provider.apiKey.keychainAccount {
                accounts.insert(account)
            }
        }
        for provider in library.universalProviders {
            if let account = provider.apiKey.keychainAccount {
                accounts.insert(account)
            }
        }
        return accounts
    }

    private func readCodexLive() async throws -> (auth: [String: String], config: String) {
        let authURL = codexAuthURL
        let configURL = codexConfigURL
        return try await Task.detached(priority: .utility) {
            let auth: [String: String]
            if FileManager.default.fileExists(atPath: authURL.path),
               let data = try? Data(contentsOf: authURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                auth = object.compactMapValues { $0 as? String }
            } else {
                auth = [:]
            }

            let config = FileManager.default.fileExists(atPath: configURL.path)
                ? (try String(contentsOf: configURL, encoding: .utf8))
                : ""
            return (auth, config)
        }.value
    }

    private func writeLiveConfig(for provider: CLIAPIProvider) async throws {
        let config = renderCodexConfig(provider: provider)
        let key = resolvedAPIKey(for: provider.apiKey)
        let authURL = codexAuthURL
        let configURL = codexConfigURL
        try await Task.detached(priority: .utility) {
            try Self.writeCodexLive(configFragment: config, apiKey: key, authURL: authURL, configURL: configURL)
        }.value
    }

    private func backupLiveFiles(for cli: APIProviderCLI, providerID: String) async throws -> URL {
        let backupsDirectory = backupsDirectory
        let sources = [codexAuthURL, codexConfigURL]
        return try await Task.detached(priority: .utility) {
            let date = Date()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
            let directory = backupsDirectory.appendingPathComponent("\(stamp)-\(cli.rawValue)-\(providerID)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var entries: [[String: Any]] = []
            for (index, source) in sources.enumerated() {
                let exists = FileManager.default.fileExists(atPath: source.path)
                if exists {
                    let backup = directory.appendingPathComponent("\(index)-\(source.lastPathComponent)", isDirectory: false)
                    try FileManager.default.copyItem(at: source, to: backup)
                    entries.append(["targetPath": source.path, "backupPath": backup.path, "existed": true])
                } else {
                    entries.append(["targetPath": source.path, "existed": false])
                }
            }

            let manifest: [String: Any] = [
                "providerID": providerID,
                "cli": cli.rawValue,
                "createdAt": ISO8601DateFormatter().string(from: date),
                "files": entries,
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("manifest.json", isDirectory: false), options: .atomic)
            return directory
        }.value
    }

    private func backfilledProvider(_ provider: CLIAPIProvider, keyStorageMode: APIProviderKeyStorageMode) async throws -> CLIAPIProvider {
        let live = try await readCodexLive()
        var updated = try providerFromCodexRaw(
            id: provider.id,
            name: provider.name,
            origin: provider.origin,
            category: provider.category,
            rawConfig: live.config,
            authJSON: live.auth,
            keyStorageMode: keyStorageMode,
            createdAt: provider.createdAt
        )
        updated.iconName = provider.iconName
        updated.iconColorHex = provider.iconColorHex
        updated.updatedAt = .now
        return updated
    }

    private func providerFromCodexRaw(
        id: String,
        name: String,
        origin: APIProviderOrigin,
        category: APIProviderCategory,
        rawConfig: String,
        authJSON: [String: String],
        keyStorageMode: APIProviderKeyStorageMode,
        createdAt: Date,
        updatedAt: Date = .now
    ) throws -> CLIAPIProvider {
        let parsed = Self.parseCodexProviderFields(rawConfig)
        let apiKey = authJSON["OPENAI_API_KEY"] ?? ""
        var provider = CLIAPIProvider(
            id: id,
            cli: .codex,
            origin: origin,
            name: name,
            category: category,
            baseURL: parsed.baseURL,
            apiKey: try storedSecret(rawKey: apiKey, cli: .codex, providerID: id, keyStorageMode: keyStorageMode),
            model: parsed.model,
            rawConfig: rawConfig,
            iconName: "openai",
            iconColorHex: "#00A67E",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        return provider
    }

    private func storedSecret(
        rawKey: String,
        cli: APIProviderCLI,
        providerID: String,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> APIProviderSecret {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        switch keyStorageMode {
        case .json:
            return .inline(trimmed)
        case .keychain:
            let account = "\(cli.rawValue)-\(providerID)"
            try secretStore.saveAPIKey(trimmed, account: account)
            return .keychain(account: account)
        }
    }

    private func storedRawConfig(for provider: CLIAPIProvider, keyStorageMode: APIProviderKeyStorageMode) -> String {
        renderCodexConfig(provider: provider)
    }

    private func renderCodexConfig(provider: CLIAPIProvider) -> String {
        guard !provider.baseURL.isEmpty || !provider.model.isEmpty else { return "" }
        let key = Self.codexProviderKey(for: provider)
        let model = provider.model.isEmpty ? defaultModel(for: .codex) : provider.model
        var lines = [
            "model_provider = \"\(key)\"",
            "model = \"\(Self.tomlEscape(model))\"",
            "model_reasoning_effort = \"high\"",
            "disable_response_storage = true",
            "",
            "[model_providers.\(key)]",
            "name = \"\(Self.tomlEscape(provider.name))\"",
        ]
        if !provider.baseURL.isEmpty {
            lines.append("base_url = \"\(Self.tomlEscape(provider.baseURL))\"")
        }
        lines.append("wire_api = \"responses\"")
        lines.append("requires_openai_auth = true")
        return lines.joined(separator: "\n")
    }

    private func defaultModel(for _: APIProviderCLI) -> String {
        "gpt-5.4"
    }

    private static func writeCodexLive(configFragment: String, apiKey: String, authURL: URL, configURL: URL) throws {
        try FileManager.default.createDirectory(at: authURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let auth: [String: String] = apiKey.isEmpty ? [:] : ["OPENAI_API_KEY": apiKey]
        let authData = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys])
        try authData.write(to: authURL, options: .atomic)

        let current = FileManager.default.fileExists(atPath: configURL.path)
            ? (try String(contentsOf: configURL, encoding: .utf8))
            : ""
        let common = stripCodexManagedConfig(from: current)
        let fragment = configFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = [fragment, common]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try next.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func parseCodexProviderFields(_ raw: String) -> (baseURL: String, model: String) {
        let model = firstTomlValue(named: "model", in: raw) ?? ""
        let baseURL = firstTomlValue(named: "base_url", in: raw) ?? ""
        return (baseURL, model)
    }

    private static func firstTomlValue(named key: String, in raw: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^\s*\#(escapedKey)\s*=\s*"([^"]*)"\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRaw = raw as NSString
        let range = NSRange(location: 0, length: nsRaw.length)
        guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        return nsRaw.substring(with: match.range(at: 1))
    }

    private static func codexProviderKey(for provider: CLIAPIProvider) -> String {
        let cleaned = provider.name
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "_" { return character }
                return "_"
            }
        let value = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.isEmpty ? "custom" : value
    }

    private static func tomlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func stripCodexManagedConfig(from raw: String) -> String {
        var output: [String] = []
        var skippingModelProviderTable = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[model_providers.") {
                skippingModelProviderTable = true
                continue
            }
            if skippingModelProviderTable, trimmed.hasPrefix("["), !trimmed.hasPrefix("[model_providers.") {
                skippingModelProviderTable = false
            }
            if skippingModelProviderTable { continue }
            if trimmed.hasPrefix("model_provider")
                || trimmed.hasPrefix("model =")
                || trimmed.hasPrefix("model_reasoning_effort")
                || trimmed.hasPrefix("disable_response_storage") {
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension JSONEncoder {
    static var apiProviderEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var apiProviderDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
