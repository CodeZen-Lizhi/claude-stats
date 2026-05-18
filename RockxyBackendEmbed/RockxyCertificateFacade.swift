import Foundation

public struct RockxyCertificateSnapshot: Sendable, Hashable {
    public let rootCAPath: String?
    public let hasGeneratedCertificate: Bool
    public let isInstalledInKeychain: Bool
    public let hasTrustSettings: Bool
    public let isSystemTrustValidated: Bool
    public let notValidBefore: Date?
    public let notValidAfter: Date?
    public let fingerprintSHA256: String?
    public let commonName: String?
    public let lastValidationErrorMessage: String?

    public init(
        rootCAPath: String?,
        hasGeneratedCertificate: Bool,
        isInstalledInKeychain: Bool,
        hasTrustSettings: Bool,
        isSystemTrustValidated: Bool,
        notValidBefore: Date?,
        notValidAfter: Date?,
        fingerprintSHA256: String?,
        commonName: String?,
        lastValidationErrorMessage: String?
    ) {
        self.rootCAPath = rootCAPath
        self.hasGeneratedCertificate = hasGeneratedCertificate
        self.isInstalledInKeychain = isInstalledInKeychain
        self.hasTrustSettings = hasTrustSettings
        self.isSystemTrustValidated = isSystemTrustValidated
        self.notValidBefore = notValidBefore
        self.notValidAfter = notValidAfter
        self.fingerprintSHA256 = fingerprintSHA256
        self.commonName = commonName
        self.lastValidationErrorMessage = lastValidationErrorMessage
    }
}

public enum RockxyCertificateController {
    public static func generateRootCA() async throws -> RockxyCertificateSnapshot {
        try await CertificateManager.shared.ensureRootCA()
        return await snapshot(performValidation: false)
    }

    public static func installAndTrustRootCA() async throws -> RockxyCertificateSnapshot {
        try await CertificateManager.shared.installAndTrust()
        return await snapshot(performValidation: true)
    }

    public static func snapshot(performValidation: Bool) async -> RockxyCertificateSnapshot {
        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: performValidation)
        return RockxyCertificateSnapshot(
            rootCAPath: snapshot.hasGeneratedCertificate ? rootCAPath.path : nil,
            hasGeneratedCertificate: snapshot.hasGeneratedCertificate,
            isInstalledInKeychain: snapshot.isInstalledInKeychain,
            hasTrustSettings: snapshot.hasTrustSettings,
            isSystemTrustValidated: snapshot.isSystemTrustValidated,
            notValidBefore: snapshot.notValidBefore,
            notValidAfter: snapshot.notValidAfter,
            fingerprintSHA256: snapshot.fingerprintSHA256,
            commonName: snapshot.commonName,
            lastValidationErrorMessage: snapshot.lastValidationErrorMessage
        )
    }

    private static var rootCAPath: URL {
        RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
            .appendingPathComponent("rootCA.pem", isDirectory: false)
    }
}
