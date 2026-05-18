import Foundation
import ServiceManagement

public enum RockxyHelperStatus: String, Sendable, Hashable {
    case disabledForUnsignedBuild
    case notInstalled
    case requiresApproval
    case installedCompatible
    case installedOutdated
    case installedIncompatible
    case unreachable
    case signingMismatch
}

public enum RockxyHelperAction: String, Sendable, Hashable {
    case install
    case update
    case retry
    case reinstall
    case openSettings
}

public struct RockxyHelperSnapshot: Sendable, Hashable {
    public let status: RockxyHelperStatus
    public let action: RockxyHelperAction?
    public let isReachable: Bool
    public let registrationStatus: String
    public let installedVersion: String?
    public let installedBuild: Int?
    public let installedProtocolVersion: Int?
    public let bundledVersion: String
    public let bundledBuild: Int
    public let expectedProtocolVersion: Int
    public let lastErrorMessage: String?
    public let statusMessage: String
    public let canUsePrivilegedHelper: Bool

    public init(
        status: RockxyHelperStatus,
        action: RockxyHelperAction?,
        isReachable: Bool,
        registrationStatus: String,
        installedVersion: String?,
        installedBuild: Int?,
        installedProtocolVersion: Int?,
        bundledVersion: String,
        bundledBuild: Int,
        expectedProtocolVersion: Int,
        lastErrorMessage: String?,
        statusMessage: String,
        canUsePrivilegedHelper: Bool
    ) {
        self.status = status
        self.action = action
        self.isReachable = isReachable
        self.registrationStatus = registrationStatus
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        self.installedProtocolVersion = installedProtocolVersion
        self.bundledVersion = bundledVersion
        self.bundledBuild = bundledBuild
        self.expectedProtocolVersion = expectedProtocolVersion
        self.lastErrorMessage = lastErrorMessage
        self.statusMessage = statusMessage
        self.canUsePrivilegedHelper = canUsePrivilegedHelper
    }
}

public enum RockxyHelperFacadeError: LocalizedError, Sendable {
    case unsignedBuild
    case helperUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsignedBuild:
            "Rockxy helper is embedded, but privileged helper operations require a signed build."
        case .helperUnavailable(let message):
            message
        }
    }
}

@MainActor
public final class RockxyHelperController {
    public static let shared = RockxyHelperController()

    private init() {}

    public func currentSnapshot() -> RockxyHelperSnapshot {
        guard Self.currentBuildAllowsPrivilegedHelper else {
            return Self.unsignedBuildSnapshot()
        }
        return Self.snapshot(from: HelperManager.shared)
    }

    @discardableResult
    public func refreshStatus() async -> RockxyHelperSnapshot {
        guard Self.currentBuildAllowsPrivilegedHelper else {
            return Self.unsignedBuildSnapshot()
        }
        await HelperManager.shared.checkStatus()
        return Self.snapshot(from: HelperManager.shared)
    }

    @discardableResult
    public func install() async throws -> RockxyHelperSnapshot {
        try Self.requirePrivilegedHelperAllowed()
        try await HelperManager.shared.install()
        return Self.snapshot(from: HelperManager.shared)
    }

    @discardableResult
    public func update() async throws -> RockxyHelperSnapshot {
        try Self.requirePrivilegedHelperAllowed()
        try await HelperManager.shared.update()
        return Self.snapshot(from: HelperManager.shared)
    }

    @discardableResult
    public func retryConnection() async -> RockxyHelperSnapshot {
        guard Self.currentBuildAllowsPrivilegedHelper else {
            return Self.unsignedBuildSnapshot()
        }
        await HelperManager.shared.retryConnection()
        return Self.snapshot(from: HelperManager.shared)
    }

    @discardableResult
    public func reinstall() async throws -> RockxyHelperSnapshot {
        try Self.requirePrivilegedHelperAllowed()
        try await HelperManager.shared.reinstall()
        return Self.snapshot(from: HelperManager.shared)
    }

    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public func overrideSystemProxy(port: UInt16) async throws {
        let snapshot = await refreshStatus()
        guard snapshot.canUsePrivilegedHelper else {
            throw RockxyHelperFacadeError.helperUnavailable(snapshot.lastErrorMessage ?? snapshot.statusMessage)
        }
        try await HelperConnection.shared.overrideSystemProxy(port: Int(port))
    }

    public func restoreSystemProxy() async throws {
        let snapshot = currentSnapshot()
        guard snapshot.canUsePrivilegedHelper else {
            throw RockxyHelperFacadeError.helperUnavailable(snapshot.lastErrorMessage ?? snapshot.statusMessage)
        }
        try await HelperConnection.shared.restoreSystemProxy()
    }

    public static var currentBuildAllowsPrivilegedHelper: Bool {
        switch SigningDiagnostics.diagnose() {
        case .healthy:
            true
        case .appSignatureInvalid,
             .signingIdentityMismatch,
             .helperBinaryNotFound,
             .certificateChainUnavailable,
             .diagnosticError:
            false
        }
    }

    private static func requirePrivilegedHelperAllowed() throws {
        guard currentBuildAllowsPrivilegedHelper else {
            throw RockxyHelperFacadeError.unsignedBuild
        }
    }

    private static func unsignedBuildSnapshot() -> RockxyHelperSnapshot {
        let manager = HelperManager.shared
        return RockxyHelperSnapshot(
            status: .disabledForUnsignedBuild,
            action: nil,
            isReachable: false,
            registrationStatus: "Embedded",
            installedVersion: nil,
            installedBuild: nil,
            installedProtocolVersion: nil,
            bundledVersion: manager.bundledHelperVersion,
            bundledBuild: manager.bundledHelperBuild,
            expectedProtocolVersion: manager.expectedProtocolVersion,
            lastErrorMessage: nil,
            statusMessage: "Helper embedded. Use a signed build to enable privileged helper operations.",
            canUsePrivilegedHelper: false
        )
    }

    private static func snapshot(from manager: HelperManager) -> RockxyHelperSnapshot {
        let status = RockxyHelperStatus(manager.status)
        return RockxyHelperSnapshot(
            status: status,
            action: RockxyHelperAction(status: manager.status, signingIssue: manager.signingIssue),
            isReachable: manager.isReachable,
            registrationStatus: manager.registrationStatus,
            installedVersion: manager.installedInfo?.binaryVersion,
            installedBuild: manager.installedInfo?.buildNumber,
            installedProtocolVersion: manager.installedInfo?.protocolVersion,
            bundledVersion: manager.bundledHelperVersion,
            bundledBuild: manager.bundledHelperBuild,
            expectedProtocolVersion: manager.expectedProtocolVersion,
            lastErrorMessage: manager.lastErrorMessage,
            statusMessage: status.statusMessage,
            canUsePrivilegedHelper: status == .installedCompatible && manager.isReachable
        )
    }
}

private extension RockxyHelperStatus {
    init(_ status: HelperManager.HelperStatus) {
        switch status {
        case .notInstalled:
            self = .notInstalled
        case .requiresApproval:
            self = .requiresApproval
        case .installedCompatible:
            self = .installedCompatible
        case .installedOutdated:
            self = .installedOutdated
        case .installedIncompatible:
            self = .installedIncompatible
        case .unreachable:
            self = .unreachable
        case .signingMismatch:
            self = .signingMismatch
        }
    }

    var statusMessage: String {
        switch self {
        case .disabledForUnsignedBuild:
            "Helper embedded. Use a signed build to enable privileged helper operations."
        case .notInstalled:
            "Helper not installed"
        case .requiresApproval:
            "Approve helper in System Settings"
        case .installedCompatible:
            "Helper installed"
        case .installedOutdated:
            "Helper update available"
        case .installedIncompatible:
            "Helper protocol mismatch"
        case .unreachable:
            "Helper unreachable"
        case .signingMismatch:
            "Helper signing mismatch"
        }
    }
}

private extension RockxyHelperAction {
    init?(status: HelperManager.HelperStatus, signingIssue: HelperManager.SigningIssue?) {
        switch status {
        case .installedCompatible:
            return nil
        case .notInstalled:
            self = .install
        case .requiresApproval:
            self = .openSettings
        case .installedOutdated,
             .installedIncompatible:
            self = .update
        case .unreachable:
            self = .retry
        case .signingMismatch:
            switch signingIssue {
            case .identityMismatch:
                self = .reinstall
            case .appSignatureInvalid, nil:
                return nil
            }
        }
    }
}
