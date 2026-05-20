import Foundation
import Security

protocol LinuxDoCredentialStoring: Sendable {
    func readAPIKey() -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey()
    func readWebSession() -> LinuxDoWebSession?
    func saveWebSession(_ session: LinuxDoWebSession) throws
    func deleteWebSession()
    func readClientID() -> String
    func saveClientID(_ clientID: String)
}

extension LinuxDoCredentialStoring {
    func readAuthCredential() -> LinuxDoAuthCredential? {
        if let apiKey = readAPIKey() {
            return .userAPIKey(key: apiKey, clientID: readClientID())
        }
        if let session = readWebSession(), session.isAuthenticated {
            return .webSession(session)
        }
        return nil
    }
}

struct LinuxDoKeychainStore: LinuxDoCredentialStoring {
    static let shared = LinuxDoKeychainStore()

    private let service = "com.claudestats.linuxdo"
    private let apiKeyAccount = "linux.do:default"
    private let webSessionAccount = "linux.do:web-session"
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

    func readWebSession() -> LinuxDoWebSession? {
        guard let data = readData(account: webSessionAccount) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(LinuxDoWebSession.self, from: data)
        } catch {
            Log.app.error("LinuxDo web session decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveWebSession(_ session: LinuxDoWebSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(session)
        try saveData(data, account: webSessionAccount)
    }

    func deleteWebSession() {
        delete(account: webSessionAccount)
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
        guard let data = readData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readData(account: String) -> Data? {
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
            return item as? Data
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
        try saveData(data, account: account)
    }

    private func saveData(_ data: Data, account: String) throws {
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
    private var webSession: LinuxDoWebSession?

    init(apiKey: String? = nil, clientID: String = "test-client-id", webSession: LinuxDoWebSession? = nil) {
        self.apiKey = apiKey
        self.clientID = clientID
        self.webSession = webSession
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

    func readWebSession() -> LinuxDoWebSession? {
        lock.withLock { webSession }
    }

    func saveWebSession(_ session: LinuxDoWebSession) {
        lock.withLock { webSession = session }
    }

    func deleteWebSession() {
        lock.withLock { webSession = nil }
    }

    func readClientID() -> String {
        lock.withLock { clientID }
    }

    func saveClientID(_ clientID: String) {
        lock.withLock { self.clientID = clientID }
    }
}
