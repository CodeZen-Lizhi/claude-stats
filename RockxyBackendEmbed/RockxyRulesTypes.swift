import Foundation

public enum RockxyRuleActionKind: String, CaseIterable, Sendable, Hashable, Codable {
    case block
    case mapLocal
    case mapRemote
    case modifyHeaders
    case throttle
    case networkCondition
    case breakpoint
    case script
}

public enum RockxyRuleMatchMethod: String, CaseIterable, Sendable, Hashable, Codable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}

public enum RockxyRuleHeaderOperationKind: String, CaseIterable, Sendable, Hashable, Codable {
    case add
    case remove
    case replace
}

public enum RockxyRuleHeaderOperationPhase: String, CaseIterable, Sendable, Hashable, Codable {
    case request
    case response
    case both
}

public struct RockxyRuleHeaderOperationSnapshot: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var kind: RockxyRuleHeaderOperationKind
    public var phase: RockxyRuleHeaderOperationPhase
    public var name: String
    public var value: String

    public init(
        id: UUID = UUID(),
        kind: RockxyRuleHeaderOperationKind,
        phase: RockxyRuleHeaderOperationPhase,
        name: String,
        value: String
    ) {
        self.id = id
        self.kind = kind
        self.phase = phase
        self.name = name
        self.value = value
    }
}

public enum RockxyBreakpointPhaseSnapshot: String, CaseIterable, Sendable, Hashable, Codable {
    case request
    case response
    case both
}

public enum RockxyScriptRuleMode: String, CaseIterable, Sendable, Hashable, Codable {
    case transform
    case mock
}

public struct RockxyRuleActionSnapshot: Sendable, Hashable, Codable {
    public var kind: RockxyRuleActionKind
    public var blockStatusCode: Int
    public var mapLocalPath: String
    public var mapLocalStatusCode: Int
    public var mapLocalIsDirectory: Bool
    public var mapRemoteScheme: String?
    public var mapRemoteHost: String?
    public var mapRemotePort: Int?
    public var mapRemotePath: String?
    public var mapRemoteQuery: String?
    public var mapRemotePreserveHostHeader: Bool
    public var headerOperations: [RockxyRuleHeaderOperationSnapshot]
    public var throttleDelayMs: Int
    public var networkConditionPreset: String
    public var networkConditionDelayMs: Int
    public var breakpointPhase: RockxyBreakpointPhaseSnapshot
    public var scriptMode: RockxyScriptRuleMode
    public var scriptSource: String
    public var scriptRunOnRequest: Bool
    public var scriptRunOnResponse: Bool

    public init(
        kind: RockxyRuleActionKind,
        blockStatusCode: Int = 403,
        mapLocalPath: String = "",
        mapLocalStatusCode: Int = 200,
        mapLocalIsDirectory: Bool = false,
        mapRemoteScheme: String? = nil,
        mapRemoteHost: String? = nil,
        mapRemotePort: Int? = nil,
        mapRemotePath: String? = nil,
        mapRemoteQuery: String? = nil,
        mapRemotePreserveHostHeader: Bool = false,
        headerOperations: [RockxyRuleHeaderOperationSnapshot] = [],
        throttleDelayMs: Int = 500,
        networkConditionPreset: String = "custom",
        networkConditionDelayMs: Int = 1_000,
        breakpointPhase: RockxyBreakpointPhaseSnapshot = .both,
        scriptMode: RockxyScriptRuleMode = .transform,
        scriptSource: String = "",
        scriptRunOnRequest: Bool = true,
        scriptRunOnResponse: Bool = true
    ) {
        self.kind = kind
        self.blockStatusCode = blockStatusCode
        self.mapLocalPath = mapLocalPath
        self.mapLocalStatusCode = mapLocalStatusCode
        self.mapLocalIsDirectory = mapLocalIsDirectory
        self.mapRemoteScheme = mapRemoteScheme
        self.mapRemoteHost = mapRemoteHost
        self.mapRemotePort = mapRemotePort
        self.mapRemotePath = mapRemotePath
        self.mapRemoteQuery = mapRemoteQuery
        self.mapRemotePreserveHostHeader = mapRemotePreserveHostHeader
        self.headerOperations = headerOperations
        self.throttleDelayMs = throttleDelayMs
        self.networkConditionPreset = networkConditionPreset
        self.networkConditionDelayMs = networkConditionDelayMs
        self.breakpointPhase = breakpointPhase
        self.scriptMode = scriptMode
        self.scriptSource = scriptSource
        self.scriptRunOnRequest = scriptRunOnRequest
        self.scriptRunOnResponse = scriptRunOnResponse
    }
}

public struct RockxyProxyRuleSnapshot: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var urlPattern: String
    public var method: RockxyRuleMatchMethod
    public var headerName: String?
    public var headerValue: String?
    public var priority: Int
    public var action: RockxyRuleActionSnapshot
    public var lastError: String?

    public init(
        id: UUID,
        name: String,
        isEnabled: Bool,
        urlPattern: String,
        method: RockxyRuleMatchMethod,
        headerName: String? = nil,
        headerValue: String? = nil,
        priority: Int,
        action: RockxyRuleActionSnapshot,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.method = method
        self.headerName = headerName
        self.headerValue = headerValue
        self.priority = priority
        self.action = action
        self.lastError = lastError
    }

    public var summary: String {
        "\(action.kind.rawValue) · \(method.rawValue) · \(urlPattern)"
    }
}

public struct RockxyRuleMatchSnapshot: Sendable, Hashable {
    public var matches: Bool
    public var message: String

    public init(matches: Bool, message: String) {
        self.matches = matches
        self.message = message
    }
}

public enum RockxyBreakpointDecisionSnapshot: String, CaseIterable, Sendable, Hashable, Codable {
    case execute
    case abort
    case cancel
}

public struct RockxyBreakpointItemSnapshot: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var phase: RockxyBreakpointPhaseSnapshot
    public var method: String
    public var url: String
    public var headers: [RockxyCapturedHeader]
    public var body: String
    public var statusCode: Int?
    public var createdAt: Date

    public init(
        id: UUID,
        phase: RockxyBreakpointPhaseSnapshot,
        method: String,
        url: String,
        headers: [RockxyCapturedHeader],
        body: String,
        statusCode: Int?,
        createdAt: Date
    ) {
        self.id = id
        self.phase = phase
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.statusCode = statusCode
        self.createdAt = createdAt
    }
}

public enum RockxyPluginStatusSnapshot: String, Sendable, Hashable, Codable {
    case active
    case disabled
    case loading
    case error
}

public struct RockxyPluginSnapshot: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String
    public var summary: String
    public var bundlePath: String
    public var isEnabled: Bool
    public var status: RockxyPluginStatusSnapshot
    public var statusMessage: String
    public var lastError: String?
    public var configurationFields: [String: String]

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        summary: String,
        bundlePath: String,
        isEnabled: Bool,
        status: RockxyPluginStatusSnapshot,
        statusMessage: String,
        lastError: String?,
        configurationFields: [String: String]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.bundlePath = bundlePath
        self.isEnabled = isEnabled
        self.status = status
        self.statusMessage = statusMessage
        self.lastError = lastError
        self.configurationFields = configurationFields
    }
}

public struct RockxyReplayRequest: Sendable, Hashable {
    public var id: UUID
    public var method: String
    public var url: URL
    public var headers: [RockxyCapturedHeader]
    public var body: Data?
    public var contentType: String?

    public init(
        id: UUID = UUID(),
        method: String,
        url: URL,
        headers: [RockxyCapturedHeader],
        body: Data?,
        contentType: String?
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.contentType = contentType
    }
}

public struct RockxyReplayResult: Sendable, Hashable {
    public var transaction: RockxyCapturedTransaction

    public init(transaction: RockxyCapturedTransaction) {
        self.transaction = transaction
    }
}
