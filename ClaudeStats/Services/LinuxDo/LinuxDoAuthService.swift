import AppKit
import AuthenticationServices
import Foundation
import Security

@MainActor
final class LinuxDoAuthService: NSObject {
    enum AuthError: Error, Sendable, CustomStringConvertible, Equatable {
        case invalidURL
        case cancelled
        case missingPayload
        case keyGenerationFailed
        case decryptionFailed
        case nonceMismatch
        case invalidPayload
        case saveFailed(String)

        var description: String {
            switch self {
            case .invalidURL:
                "Could not create the LinuxDo sign-in URL."
            case .cancelled:
                "Sign in was cancelled."
            case .missingPayload:
                "Linux.do did not return an API key payload."
            case .keyGenerationFailed:
                "Could not create a temporary encryption key."
            case .decryptionFailed:
                "Could not decrypt the Linux.do sign-in response."
            case .nonceMismatch:
                "Linux.do returned a sign-in response for a different request."
            case .invalidPayload:
                "Linux.do returned an unexpected sign-in response."
            case .saveFailed:
                "Could not save the Linux.do API key."
            }
        }
    }

    struct AuthPayload: Decodable, Sendable, Equatable {
        let key: String
        let nonce: String
        let api: Int?
        let push: Bool?
    }

    private let credentials: any LinuxDoCredentialStoring
    private let baseURL: URL
    private var presentationProvider: PresentationProvider?
    private var authSession: ASWebAuthenticationSession?

    init(
        baseURL: URL = URL(string: "https://linux.do")!,
        credentials: any LinuxDoCredentialStoring = LinuxDoKeychainStore.shared
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
    }

    func login(presentationAnchor: ASPresentationAnchor) async throws -> AuthPayload {
        let clientID = credentials.readClientID()
        let nonce = Self.makeNonce()
        let privateKey = try Self.generatePrivateKey()
        let publicKeyPEM = try Self.publicKeyPEM(from: privateKey)
        let authURL = try Self.authURL(
            baseURL: baseURL,
            clientID: clientID,
            nonce: nonce,
            publicKeyPEM: publicKeyPEM
        )
        let callbackURL = try await startAuthentication(url: authURL, presentationAnchor: presentationAnchor)
        let encryptedPayload = try Self.payload(from: callbackURL)
        let payload = try Self.decryptPayload(encryptedPayload, privateKey: privateKey)
        guard payload.nonce == nonce else {
            throw AuthError.nonceMismatch
        }
        do {
            try credentials.saveAPIKey(payload.key)
        } catch {
            throw AuthError.saveFailed(error.localizedDescription)
        }
        credentials.saveClientID(clientID)
        return payload
    }

    nonisolated static func authURL(
        baseURL: URL,
        clientID: String,
        nonce: String,
        publicKeyPEM: String
    ) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("user-api-key/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "application_name", value: "Claude Stats"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scopes", value: "read,notifications,session_info"),
            URLQueryItem(name: "public_key", value: publicKeyPEM),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "auth_redirect", value: "claude-stats://linuxdo-auth"),
            URLQueryItem(name: "padding", value: "oaep"),
        ]
        guard let url = components?.url else { throw AuthError.invalidURL }
        return url
    }

    nonisolated static func payload(from callbackURL: URL) throws -> String {
        guard callbackURL.scheme == "claude-stats",
              callbackURL.host == "linuxdo-auth" || callbackURL.path == "/linuxdo-auth",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              !payload.isEmpty else {
            throw AuthError.missingPayload
        }
        return payload
    }

    nonisolated static func decryptPayload(_ encryptedPayload: String, privateKey: SecKey) throws -> AuthPayload {
        var base64 = encryptedPayload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let encrypted = Data(base64Encoded: base64) else {
            throw AuthError.invalidPayload
        }

        let algorithms: [SecKeyAlgorithm] = [
            .rsaEncryptionOAEPSHA256,
            .rsaEncryptionOAEPSHA1,
            .rsaEncryptionPKCS1,
        ]
        for algorithm in algorithms where SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) {
            var error: Unmanaged<CFError>?
            if let decrypted = SecKeyCreateDecryptedData(privateKey, algorithm, encrypted as CFData, &error) as Data? {
                do {
                    return try JSONDecoder().decode(AuthPayload.self, from: decrypted)
                } catch {
                    throw AuthError.invalidPayload
                }
            }
        }
        throw AuthError.decryptionFailed
    }

    private func startAuthentication(url: URL, presentationAnchor: ASPresentationAnchor) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let provider = PresentationProvider(anchor: presentationAnchor)
            presentationProvider = provider
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "claude-stats") { [weak self] callbackURL, error in
                self?.presentationProvider = nil
                self?.authSession = nil
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.missingPayload)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                presentationProvider = nil
                authSession = nil
                continuation.resume(throwing: AuthError.invalidURL)
            }
        }
    }

    private static func generatePrivateKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw AuthError.keyGenerationFailed
        }
        return privateKey
    }

    private static func publicKeyPEM(from privateKey: SecKey) throws -> String {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw AuthError.keyGenerationFailed
        }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw AuthError.keyGenerationFailed
        }
        let base64 = data.base64EncodedString(options: [.lineLength64Characters])
        return """
        -----BEGIN PUBLIC KEY-----
        \(base64)
        -----END PUBLIC KEY-----
        """
    }

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor

        init(anchor: ASPresentationAnchor) {
            self.anchor = anchor
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
}
