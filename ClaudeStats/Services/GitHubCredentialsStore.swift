import Foundation
import Security

/// Stores the user's GitHub personal access token in the macOS Keychain.
/// V1 supports a single account — `account` is a constant. The struct itself
/// is `Sendable` because every method goes through the Keychain rather than
/// holding the token in memory; callers fetch lazily right before a request.
struct GitHubCredentialsStore: Sendable {
    static let shared = GitHubCredentialsStore()

    private let service = "com.claudestats.github"
    private let account = "default"

    /// Returns the stored token, or `nil` if there isn't one (or the read
    /// failed — failures are logged, not surfaced; the UI treats both
    /// indistinguishably as "not connected").
    func readToken() -> String? {
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
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            Log.app.error("Keychain read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    /// Save or replace the token. Throws `KeychainError` on failure so the
    /// caller can surface "couldn't save token" in the UI.
    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidToken
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

    /// Remove the token. Missing-item is treated as success.
    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.app.error("Keychain delete failed: OSStatus \(status, privacy: .public)")
        }
    }

    enum KeychainError: Error, Sendable {
        case invalidToken
        case osStatus(OSStatus)
    }
}
