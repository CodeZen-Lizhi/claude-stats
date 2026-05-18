import AppKit
import Foundation

enum BreakpointPhase {
    case request
    case response
}

enum BreakpointDecision {
    case execute
    case abort
    case cancel
}

struct EditableHeader: Identifiable {
    let id = UUID()
    var name: String
    var value: String
}

struct BreakpointRequestData {
    var method: String
    var url: String
    var headers: [EditableHeader]
    var body: String
    var statusCode: Int
    var phase: BreakpointPhase = .request

    var isHTTPS: Bool {
        url.lowercased().hasPrefix("https://")
    }
}

enum RequestHookOutcome {
    case forward(HTTPRequestData)
    case blockLocally
    case mock(HTTPResponseData)
    case mockFailure
}

enum HelperManager {
    enum HelperStatus: Equatable {
        case notInstalled
        case requiresApproval
        case installedCompatible
        case installedOutdated
        case installedIncompatible
        case unreachable
        case signingMismatch
    }

    @MainActor
    static let shared = HelperManagerState()
}

@MainActor
final class HelperManagerState {
    let status: HelperManager.HelperStatus = .notInstalled
    let isReachable = false
}

actor HelperConnection {
    static let shared = HelperConnection()

    func cleanupStaleCertificates(activeFingerprint _: String) async throws -> Int {
        0
    }

    func installRootCertificate(derData _: Data) async throws {}
}

actor ScriptPluginManager {
    func runRequestHook(on request: HTTPRequestData) async -> RequestHookOutcome {
        .forward(request)
    }

    func runResponseHook(request: HTTPRequestData, response: HTTPResponseData) async -> HTTPResponseData {
        response
    }

    nonisolated func hasResponseHookForSnapshot(request _: HTTPRequestData) -> Bool {
        false
    }
}

enum Theme {
    enum Highlight {
        static let redNS = NSColor.systemRed
        static let orangeNS = NSColor.systemOrange
        static let yellowNS = NSColor.systemYellow
        static let greenNS = NSColor.systemGreen
        static let blueNS = NSColor.systemBlue
        static let purpleNS = NSColor.systemPurple
    }
}
