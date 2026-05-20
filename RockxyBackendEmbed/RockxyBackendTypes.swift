import Foundation

public struct RockxyProxyEndpoint: Sendable, Hashable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public enum RockxyUpstreamProxyKind: String, CaseIterable, Sendable, Hashable, Codable {
    case http
    case https
    case socks5
    case pac

    public var displayName: String {
        switch self {
        case .http:
            "HTTP"
        case .https:
            "HTTPS"
        case .socks5:
            "SOCKS5"
        case .pac:
            "PAC"
        }
    }
}

public struct RockxyUpstreamProxyServer: Sendable, Hashable, Codable {
    public var kind: RockxyUpstreamProxyKind
    public var host: String
    public var port: UInt16
    public var username: String?
    public var password: String?
    public var pacScript: String?
    public var pacURL: URL?

    public init(
        kind: RockxyUpstreamProxyKind,
        host: String,
        port: UInt16,
        username: String? = nil,
        password: String? = nil,
        pacScript: String? = nil,
        pacURL: URL? = nil
    ) {
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.pacScript = pacScript
        self.pacURL = pacURL
    }

    public var displayName: String {
        switch kind {
        case .pac:
            pacURL?.absoluteString ?? "PAC"
        default:
            "\(kind.displayName) \(host):\(port)"
        }
    }
}

public struct RockxyUpstreamProxyConfiguration: Sendable, Hashable, Codable {
    public var isEnabled: Bool
    public var proxies: [RockxyUpstreamProxyServer]
    public var includeHosts: [String]
    public var excludeHosts: [String]
    public var bypassLocalhost: Bool
    public var dnsOverSocks: Bool

    public init(
        isEnabled: Bool,
        proxies: [RockxyUpstreamProxyServer],
        includeHosts: [String] = [],
        excludeHosts: [String] = [],
        bypassLocalhost: Bool = true,
        dnsOverSocks: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.proxies = proxies
        self.includeHosts = includeHosts
        self.excludeHosts = excludeHosts
        self.bypassLocalhost = bypassLocalhost
        self.dnsOverSocks = dnsOverSocks
    }

    public static let disabled = RockxyUpstreamProxyConfiguration(isEnabled: false, proxies: [])
}

public struct RockxyUpstreamProxyTestResult: Sendable, Hashable {
    public let isReachable: Bool
    public let routeSummary: String
    public let errorMessage: String?

    public init(isReachable: Bool, routeSummary: String, errorMessage: String?) {
        self.isReachable = isReachable
        self.routeSummary = routeSummary
        self.errorMessage = errorMessage
    }
}

public enum RockxyProxyBackendEvent: Sendable {
    case started(RockxyProxyEndpoint)
    case stopped
    case transaction(RockxyCapturedTransaction)
    case failed(String)
}

public enum RockxyWebSocketFrameDirection: String, Sendable, Hashable, Codable {
    case sent
    case received
}

public struct RockxyWebSocketFrameSnapshot: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let direction: RockxyWebSocketFrameDirection
    public let opcode: String
    public let payload: Data
    public let isFinal: Bool

    public init(
        id: UUID,
        timestamp: Date,
        direction: RockxyWebSocketFrameDirection,
        opcode: String,
        payload: Data,
        isFinal: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.opcode = opcode
        self.payload = payload
        self.isFinal = isFinal
    }
}

public struct RockxyCapturedHeader: Sendable, Hashable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public enum RockxyCapturedTransactionState: String, Sendable, Hashable {
    case pending
    case active
    case completed
    case failed
    case blocked
}

public struct RockxyCapturedRequest: Sendable, Hashable {
    public let method: String
    public let url: URL
    public let httpVersion: String
    public let headers: [RockxyCapturedHeader]
    public let body: Data?
    public let contentType: String?

    public init(
        method: String,
        url: URL,
        httpVersion: String,
        headers: [RockxyCapturedHeader],
        body: Data?,
        contentType: String?
    ) {
        self.method = method
        self.url = url
        self.httpVersion = httpVersion
        self.headers = headers
        self.body = body
        self.contentType = contentType
    }
}

public struct RockxyCapturedResponse: Sendable, Hashable {
    public let statusCode: Int
    public let statusMessage: String
    public let headers: [RockxyCapturedHeader]
    public let body: Data?
    public let bodyTruncated: Bool
    public let contentType: String?

    public init(
        statusCode: Int,
        statusMessage: String,
        headers: [RockxyCapturedHeader],
        body: Data?,
        bodyTruncated: Bool,
        contentType: String?
    ) {
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.headers = headers
        self.body = body
        self.bodyTruncated = bodyTruncated
        self.contentType = contentType
    }
}

public struct RockxyCapturedTransaction: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let sequenceNumber: Int
    public let timestamp: Date
    public let startedAt: Date?
    public let completedAt: Date?
    public let measuredDuration: TimeInterval?
    public let establishmentDuration: TimeInterval?
    public let request: RockxyCapturedRequest
    public let response: RockxyCapturedResponse?
    public let state: RockxyCapturedTransactionState
    public let isTLSFailure: Bool
    public let isWebSocket: Bool
    public let sourcePort: UInt16?
    public let clientApp: String?
    public let clientAttribution: RockxyClientAttribution?
    public let matchedRuleName: String?
    public let matchedRuleActionSummary: String?
    public let matchedRulePattern: String?
    public let upstreamProxySummary: String?
    public let upstreamProxyKind: String?
    public let webSocketFrames: [RockxyWebSocketFrameSnapshot]

    public init(
        id: UUID,
        sequenceNumber: Int,
        timestamp: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        measuredDuration: TimeInterval?,
        establishmentDuration: TimeInterval? = nil,
        request: RockxyCapturedRequest,
        response: RockxyCapturedResponse?,
        state: RockxyCapturedTransactionState,
        isTLSFailure: Bool,
        isWebSocket: Bool,
        sourcePort: UInt16?,
        clientApp: String?,
        clientAttribution: RockxyClientAttribution? = nil,
        matchedRuleName: String?,
        matchedRuleActionSummary: String? = nil,
        matchedRulePattern: String? = nil,
        upstreamProxySummary: String? = nil,
        upstreamProxyKind: String? = nil,
        webSocketFrames: [RockxyWebSocketFrameSnapshot] = []
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.measuredDuration = measuredDuration
        self.establishmentDuration = establishmentDuration
        self.request = request
        self.response = response
        self.state = state
        self.isTLSFailure = isTLSFailure
        self.isWebSocket = isWebSocket
        self.sourcePort = sourcePort
        self.clientApp = clientApp
        self.clientAttribution = clientAttribution
        self.matchedRuleName = matchedRuleName
        self.matchedRuleActionSummary = matchedRuleActionSummary
        self.matchedRulePattern = matchedRulePattern
        self.upstreamProxySummary = upstreamProxySummary
        self.upstreamProxyKind = upstreamProxyKind
        self.webSocketFrames = webSocketFrames
    }
}

public enum RockxyClientAttribution: String, Sendable, Hashable, Codable {
    case process
    case userAgent
    case unresolved
}

public enum RockxyProxyBackendError: LocalizedError, Sendable {
    case noAvailablePort
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .noAvailablePort:
            "No available local proxy port."
        case .invalidPort(let port):
            "Invalid local proxy port: \(port)."
        }
    }
}
