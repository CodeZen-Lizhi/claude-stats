import Foundation
import Security

actor NetworkUpstreamEnvironmentStore {
    private let fileURL: URL
    private let keychainService = "com.claudestats.network.upstream"

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("ClaudeStats/Network", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("upstream-environments.json")
    }

    func load() async -> [NetworkUpstreamEnvironment] {
        do {
            let data = try Data(contentsOf: fileURL)
            let environments = try JSONDecoder().decode([NetworkUpstreamEnvironment].self, from: data)
            return environments.isEmpty ? [.default] : environments
        } catch {
            return [.default]
        }
    }

    func save(_ environments: [NetworkUpstreamEnvironment]) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(environments).write(to: fileURL, options: .atomic)
    }

    nonisolated func savePassword(_ password: String, for profileID: UUID) throws -> NetworkUpstreamCredentialRef {
        let account = profileID.uuidString.lowercased()
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NetworkUpstreamEnvironmentStoreError.keychainWriteFailed(status)
        }
        return NetworkUpstreamCredentialRef(
            username: "",
            keychainService: keychainService,
            keychainAccount: account
        )
    }

    nonisolated func password(for ref: NetworkUpstreamCredentialRef) throws -> String? {
        guard ref.hasSecretReference else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ref.keychainService,
            kSecAttrAccount as String: ref.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NetworkUpstreamEnvironmentStoreError.keychainReadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    nonisolated func deletePassword(for ref: NetworkUpstreamCredentialRef) {
        guard ref.hasSecretReference else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ref.keychainService,
            kSecAttrAccount as String: ref.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum NetworkUpstreamEnvironmentStoreError: LocalizedError, Sendable {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed(let status):
            "Could not read upstream proxy password from Keychain (\(status))."
        case .keychainWriteFailed(let status):
            "Could not save upstream proxy password to Keychain (\(status))."
        }
    }
}
