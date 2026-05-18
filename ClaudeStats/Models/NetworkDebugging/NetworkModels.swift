import Foundation

enum NetworkSection: String, CaseIterable, Identifiable, Sendable {
    case traffic
    case setup
    case certificates
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .traffic: "Traffic"
        case .setup: "Setup"
        case .certificates: "Certificates"
        case .rules: "Rules"
        }
    }

    var symbol: String {
        switch self {
        case .traffic: "list.bullet.rectangle"
        case .setup: "network"
        case .certificates: "checkmark.shield"
        case .rules: "slider.horizontal.3"
        }
    }
}

enum NetworkResolvedTrafficLayout: String, Sendable, Equatable {
    case stacked
    case sideBySide
}

enum NetworkTrafficLayoutConstants {
    static let defaultAutoBreakpoint: Double = 900
    static let minimumAutoBreakpoint: Double = 640
    static let maximumAutoBreakpoint: Double = 1600
    static let autoBreakpointStep: Double = 20

    static func clampedAutoBreakpoint(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAutoBreakpoint }
        return min(max(value, minimumAutoBreakpoint), maximumAutoBreakpoint)
    }
}

enum NetworkTrafficLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case stacked
    case sideBySide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .stacked: "Top Bottom"
        case .sideBySide: "Left Right"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "square.grid.2x2"
        case .stacked: "rectangle.split.1x2"
        case .sideBySide: "rectangle.split.2x1"
        }
    }

    var help: String {
        switch self {
        case .automatic: "Automatically arrange traffic and payload panes"
        case .stacked: "Place traffic above Request and Response panes"
        case .sideBySide: "Place traffic beside Request and Response panes"
        }
    }

    func resolved(width: Double, breakpoint: Double) -> NetworkResolvedTrafficLayout {
        switch self {
        case .automatic:
            let clampedBreakpoint = NetworkTrafficLayoutConstants.clampedAutoBreakpoint(breakpoint)
            return width < clampedBreakpoint ? .stacked : .sideBySide
        case .stacked:
            return .stacked
        case .sideBySide:
            return .sideBySide
        }
    }
}

enum NetworkInspectorSide: String, CaseIterable, Identifiable, Sendable, Hashable {
    case request
    case response

    var id: String { rawValue }

    var title: String {
        switch self {
        case .request: "Request"
        case .response: "Response"
        }
    }
}

enum NetworkInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case header
    case query
    case body
    case raw
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .header: "Header"
        case .query: "Query"
        case .body: "Body"
        case .raw: "Raw"
        case .json: "JSON"
        }
    }
}

enum NetworkFlowProtocol: String, Sendable {
    case http = "HTTP"
    case https = "HTTPS"
    case webSocket = "WebSocket"
    case tunnel = "Tunnel"
}

enum NetworkFlowState: String, Sendable {
    case active
    case completed
    case failed
}

struct NetworkHeaderPair: Identifiable, Sendable, Hashable {
    let id: String
    var name: String
    var value: String

    init(name: String, value: String) {
        self.id = "\(name.lowercased()):\(value)"
        self.name = name
        self.value = value
    }
}

struct NetworkBody: Sendable, Hashable {
    var bytes: Int
    var text: String
    var isTruncated: Bool
    var contentType: String?

    static let empty = NetworkBody(bytes: 0, text: "", isTruncated: false, contentType: nil)
}

struct NetworkRequestCapture: Sendable, Hashable {
    var method: String
    var url: String
    var httpVersion: String
    var headers: [NetworkHeaderPair]
    var body: NetworkBody

    var host: String {
        if let url = URL(string: url), let host = url.host { return host }
        return header(named: "Host") ?? ""
    }

    func header(named name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

struct NetworkResponseCapture: Sendable, Hashable {
    var statusCode: Int?
    var reason: String
    var headers: [NetworkHeaderPair]
    var body: NetworkBody

    static let empty = NetworkResponseCapture(statusCode: nil, reason: "", headers: [], body: .empty)
}

struct NetworkFlow: Identifiable, Sendable, Hashable {
    var id: UUID
    var number: Int
    var createdAt: Date
    var completedAt: Date?
    var clientName: String
    var flowProtocol: NetworkFlowProtocol
    var state: NetworkFlowState
    var request: NetworkRequestCapture
    var response: NetworkResponseCapture
    var requestBytes: Int
    var responseBytes: Int
    var isSSLIntercepted: Bool
    var isEdited: Bool
    var errorDescription: String?

    var duration: TimeInterval {
        (completedAt ?? Date()).timeIntervalSince(createdAt)
    }

    var statusDisplay: String {
        if let code = response.statusCode { return "\(code)" }
        if state == .active { return "Active" }
        if state == .failed { return "Failed" }
        return "-"
    }

    var urlDisplay: String { request.url }

    static func placeholder(now: Date = .now) -> [NetworkFlow] {
        [
            NetworkFlow(
                id: UUID(),
                number: 1,
                createdAt: now.addingTimeInterval(-18),
                completedAt: now.addingTimeInterval(-17.76),
                clientName: "Preview",
                flowProtocol: .http,
                state: .completed,
                request: NetworkRequestCapture(
                    method: "GET",
                    url: "http://httpbin.org/json",
                    httpVersion: "HTTP/1.1",
                    headers: [
                        NetworkHeaderPair(name: "Host", value: "httpbin.org"),
                        NetworkHeaderPair(name: "User-Agent", value: "Claude Stats Network"),
                        NetworkHeaderPair(name: "Accept", value: "application/json"),
                    ],
                    body: .empty
                ),
                response: NetworkResponseCapture(
                    statusCode: 200,
                    reason: "OK",
                    headers: [
                        NetworkHeaderPair(name: "Content-Type", value: "application/json"),
                        NetworkHeaderPair(name: "Server", value: "preview"),
                    ],
                    body: NetworkBody(bytes: 44, text: "{\n  \"slideshow\": {\n    \"title\": \"Sample\"\n  }\n}", isTruncated: false, contentType: "application/json")
                ),
                requestBytes: 112,
                responseBytes: 276,
                isSSLIntercepted: false,
                isEdited: false,
                errorDescription: nil
            ),
            NetworkFlow(
                id: UUID(),
                number: 2,
                createdAt: now.addingTimeInterval(-11),
                completedAt: now.addingTimeInterval(-10.91),
                clientName: "curl",
                flowProtocol: .tunnel,
                state: .completed,
                request: NetworkRequestCapture(
                    method: "CONNECT",
                    url: "https://api.openai.com:443",
                    httpVersion: "HTTP/1.1",
                    headers: [NetworkHeaderPair(name: "Host", value: "api.openai.com:443")],
                    body: .empty
                ),
                response: NetworkResponseCapture(statusCode: 200, reason: "Connection Established", headers: [], body: .empty),
                requestBytes: 0,
                responseBytes: 0,
                isSSLIntercepted: false,
                isEdited: false,
                errorDescription: nil
            ),
        ]
    }
}

struct NetworkProxyEndpoint: Sendable, Hashable {
    var host: String
    var port: UInt16

    var displayName: String { "\(host):\(port)" }
}

enum NetworkCaptureStatus: Sendable, Equatable {
    case stopped
    case starting
    case listening(NetworkProxyEndpoint)
    case failed(String)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

struct NetworkSystemProxyStatus: Sendable, Equatable {
    var isEnabled: Bool
    var managedServices: [String]
    var lastError: String?

    static let idle = NetworkSystemProxyStatus(isEnabled: false, managedServices: [], lastError: nil)
}

enum NetworkHelperAction: String, Sendable, Equatable {
    case install
    case update
    case retry
    case reinstall
    case openSettings

    var title: String {
        switch self {
        case .install:
            "Install"
        case .update:
            "Update"
        case .retry:
            "Retry"
        case .reinstall:
            "Reinstall"
        case .openSettings:
            "Open Settings"
        }
    }
}

struct NetworkHelperState: Sendable, Equatable {
    var statusMessage: String
    var detailMessage: String?
    var action: NetworkHelperAction?
    var isReachable: Bool
    var canUsePrivilegedHelper: Bool

    static let empty = NetworkHelperState(
        statusMessage: "Checking helper...",
        detailMessage: nil,
        action: nil,
        isReachable: false,
        canUsePrivilegedHelper: false
    )
}

struct NetworkCertificateState: Sendable, Equatable {
    var rootCAPath: String?
    var isTrusted: Bool
    var isMITMEnabled: Bool
    var sslHostAllowlist: [String]
    var statusMessage: String?

    static let empty = NetworkCertificateState(
        rootCAPath: nil,
        isTrusted: false,
        isMITMEnabled: false,
        sslHostAllowlist: [],
        statusMessage: nil
    )
}
