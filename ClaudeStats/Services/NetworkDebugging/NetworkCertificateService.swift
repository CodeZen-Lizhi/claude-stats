import Foundation
import RockxyBackendEmbed

struct NetworkCertificateService: Sendable {
    func generateRootCA(preserving current: NetworkCertificateState) async throws -> NetworkCertificateState {
        let snapshot = try await RockxyCertificateController.generateRootCA()
        return Self.state(from: snapshot, preserving: current, statusMessage: "Root CA generated.")
    }

    func trustRootCA(preserving current: NetworkCertificateState) async throws -> NetworkCertificateState {
        let snapshot = try await RockxyCertificateController.installAndTrustRootCA()
        return Self.state(from: snapshot, preserving: current, statusMessage: "Root CA trusted.")
    }

    static func state(
        from snapshot: RockxyCertificateSnapshot,
        preserving current: NetworkCertificateState,
        statusMessage: String?
    ) -> NetworkCertificateState {
        NetworkCertificateState(
            rootCAPath: snapshot.rootCAPath,
            isTrusted: snapshot.isSystemTrustValidated || snapshot.hasTrustSettings,
            isMITMEnabled: current.isMITMEnabled,
            sslHostAllowlist: current.sslHostAllowlist,
            statusMessage: snapshot.lastValidationErrorMessage ?? statusMessage
        )
    }
}
