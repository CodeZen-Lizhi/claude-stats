import Foundation
import Security

protocol LinuxDoCredentialStoring: Sendable {
    func readAPIKey() -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey()
    func readClientID() -> String
    func saveClientID(_ clientID: String)
}

struct LinuxDoKeychainStore: LinuxDoCredentialStoring {
    static let shared = LinuxDoKeychainStore()

    private let service = "com.claudestats.linuxdo"
    private let apiKeyAccount = "linux.do:default"
    private let clientIDKey = "LinuxDo.clientID"

    func readAPIKey() -> String? {
        read(account: apiKeyAccount)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try save(apiKey, account: apiKeyAccount)
    }

    func deleteAPIKey() {
        delete(account: apiKeyAccount)
    }

    func readClientID() -> String {
        if let stored = UserDefaults.standard.string(forKey: clientIDKey), !stored.isEmpty {
            return stored
        }
        let clientID = UUID().uuidString
        saveClientID(clientID)
        return clientID
    }

    func saveClientID(_ clientID: String) {
        UserDefaults.standard.set(clientID, forKey: clientIDKey)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            Log.app.error("LinuxDo Keychain read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    private func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidValue
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
        default:
            throw KeychainError.osStatus(updateStatus)
        }
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.app.error("LinuxDo Keychain delete failed: OSStatus \(status, privacy: .public)")
        }
    }

    enum KeychainError: Error, Sendable {
        case invalidValue
        case osStatus(OSStatus)
    }
}

final class InMemoryLinuxDoCredentialStore: LinuxDoCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var apiKey: String?
    private var clientID: String

    init(apiKey: String? = nil, clientID: String = "test-client-id") {
        self.apiKey = apiKey
        self.clientID = clientID
    }

    func readAPIKey() -> String? {
        lock.withLock { apiKey }
    }

    func saveAPIKey(_ apiKey: String) {
        lock.withLock { self.apiKey = apiKey }
    }

    func deleteAPIKey() {
        lock.withLock { apiKey = nil }
    }

    func readClientID() -> String {
        lock.withLock { clientID }
    }

    func saveClientID(_ clientID: String) {
        lock.withLock { self.clientID = clientID }
    }
}

