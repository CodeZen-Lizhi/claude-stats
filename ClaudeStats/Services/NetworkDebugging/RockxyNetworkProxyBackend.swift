import Foundation
import RockxyBackendEmbed

final class RockxyNetworkProxyBackend: NetworkProxyBackend, @unchecked Sendable {
    private let backend: RockxyProxyBackend
    private let bodyLimit: Int

    init(backend: RockxyProxyBackend = RockxyProxyBackend(), bodyLimit: Int = 2 * 1024 * 1024) {
        self.backend = backend
        self.bodyLimit = bodyLimit
    }

    func start(
        preferredPorts: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> NetworkProxyEndpoint {
        let endpoint = try await backend.start(preferredPorts: preferredPorts) { [bodyLimit] event in
            switch event {
            case .started(let endpoint):
                eventHandler(.started(NetworkProxyEndpoint(host: endpoint.host, port: endpoint.port)))
            case .stopped:
                eventHandler(.stopped)
            case .transaction(let transaction):
                eventHandler(.flowCreated(Self.flow(from: transaction, bodyLimit: bodyLimit)))
            case .failed(let message):
                eventHandler(.failed(message))
            }
        }
        return NetworkProxyEndpoint(host: endpoint.host, port: endpoint.port)
    }

    func stop() async {
        await backend.stop()
    }

    func updateUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async {
        await backend.updateUpstreamProxy(configuration.rockxyConfiguration)
    }

    func testUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async -> NetworkUpstreamProxyTestResult {
        let result = await backend.testUpstreamProxy(configuration.rockxyConfiguration)
        return NetworkUpstreamProxyTestResult(
            isReachable: result.isReachable,
            routeSummary: result.routeSummary,
            errorMessage: result.errorMessage
        )
    }

    func rules() async -> [NetworkRuleDraft] {
        await backend.rules().map(\.networkRule)
    }

    func saveRule(_ rule: NetworkRuleDraft) async throws {
        try await backend.saveRule(rule.rockxyRule)
    }

    func deleteRule(id: UUID) async throws {
        try await backend.deleteRule(id: id)
    }

    func setRuleEnabled(id: UUID, enabled: Bool) async throws {
        try await backend.setRuleEnabled(id: id, enabled: enabled)
    }

    func moveRule(id: UUID, before destinationID: UUID?) async throws {
        try await backend.moveRule(id: id, before: destinationID)
    }

    func testRule(_ rule: NetworkRuleDraft, sampleURL: URL, method: String, headers: [NetworkHeaderPair]) async -> NetworkRuleMatchSnapshot {
        let result = await backend.testRule(
            rule.rockxyRule,
            url: sampleURL,
            method: method,
            headers: headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) }
        )
        return NetworkRuleMatchSnapshot(matches: result.matches, message: result.message)
    }

    func exportRulesData() async throws -> Data {
        try await backend.exportRulesData()
    }

    func importRulesData(_ data: Data) async throws {
        try await backend.importRulesData(data)
    }

    func plugins() async -> [NetworkPluginItem] {
        await backend.plugins().map(\.networkPlugin)
    }

    func installPlugin(at path: String) async throws {
        try await backend.installPlugin(at: path)
    }

    func setPluginEnabled(id: String, enabled: Bool) async throws {
        try await backend.setPluginEnabled(id: id, enabled: enabled)
    }

    func reloadPlugin(id: String) async throws {
        try await backend.reloadPlugin(id: id)
    }

    func deletePlugin(id: String) async throws {
        try await backend.deletePlugin(id: id)
    }

    func breakpoints() async -> [NetworkBreakpointItem] {
        await backend.breakpoints().map(\.networkBreakpoint)
    }

    func updateBreakpoint(_ item: NetworkBreakpointItem) async {
        await backend.updateBreakpoint(item.rockxyBreakpoint)
    }

    func resolveBreakpoint(id: UUID, decision: NetworkBreakpointDecision) async {
        await backend.resolveBreakpoint(
            id: id,
            decision: RockxyBreakpointDecisionSnapshot(rawValue: decision.rawValue) ?? .execute
        )
    }

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow {
        guard let url = URL(string: draft.url) else {
            throw NetworkReplayError.invalidURL
        }
        let body = draft.bodyText.isEmpty ? nil : Data(draft.bodyText.utf8)
        let result = try await backend.replay(RockxyReplayRequest(
            method: draft.method,
            url: url,
            headers: draft.headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) },
            body: body,
            contentType: draft.contentType
        ))
        var flow = Self.flow(from: result.transaction, bodyLimit: bodyLimit)
        flow.isReplay = true
        return flow
    }

    static func flow(from transaction: RockxyCapturedTransaction, bodyLimit: Int = 2 * 1024 * 1024) -> NetworkFlow {
        let requestBody = body(from: transaction.request.body, contentType: transaction.request.contentType, isTruncated: false, limit: bodyLimit)
        let response = transaction.response.map { response in
            NetworkResponseCapture(
                statusCode: response.statusCode,
                reason: response.statusMessage,
                headers: response.headers.map { NetworkHeaderPair(name: $0.name, value: $0.value) },
                body: body(
                    from: response.body,
                    contentType: response.contentType,
                    isTruncated: response.bodyTruncated,
                    limit: bodyLimit
                )
            )
        } ?? .empty

        return NetworkFlow(
            id: transaction.id,
            number: transaction.sequenceNumber,
            createdAt: transaction.timestamp,
            completedAt: completedAt(for: transaction),
            clientName: transaction.clientApp ?? "Proxy Client",
            flowProtocol: flowProtocol(for: transaction),
            state: flowState(for: transaction),
            request: NetworkRequestCapture(
                method: transaction.request.method,
                url: transaction.request.url.absoluteString,
                httpVersion: transaction.request.httpVersion,
                headers: transaction.request.headers.map { NetworkHeaderPair(name: $0.name, value: $0.value) },
                body: requestBody
            ),
            response: response,
            requestBytes: transaction.request.body?.count ?? 0,
            responseBytes: transaction.response?.body?.count ?? 0,
            isSSLIntercepted: isSSLIntercepted(transaction),
            isEdited: transaction.matchedRuleName != nil,
            errorDescription: errorDescription(for: transaction),
            upstreamProxy: NetworkFlowUpstreamProxy(
                kind: transaction.upstreamProxyKind ?? "Direct",
                summary: transaction.upstreamProxySummary ?? "Direct"
            ),
            matchedRuleName: transaction.matchedRuleName,
            matchedRuleSummary: transaction.matchedRuleActionSummary,
            matchedRulePattern: transaction.matchedRulePattern,
            webSocketFrames: transaction.webSocketFrames.map(Self.webSocketFrame(from:))
        )
    }

    private static func completedAt(for transaction: RockxyCapturedTransaction) -> Date? {
        switch transaction.state {
        case .pending, .active:
            nil
        case .completed, .failed, .blocked:
            transaction.timestamp.addingTimeInterval(transaction.measuredDuration ?? 0)
        }
    }

    private static func flowState(for transaction: RockxyCapturedTransaction) -> NetworkFlowState {
        switch transaction.state {
        case .pending, .active:
            .active
        case .completed:
            .completed
        case .failed, .blocked:
            .failed
        }
    }

    private static func flowProtocol(for transaction: RockxyCapturedTransaction) -> NetworkFlowProtocol {
        if transaction.isWebSocket { return .webSocket }
        if transaction.request.method.uppercased() == "CONNECT" { return .tunnel }
        switch transaction.request.url.scheme?.lowercased() {
        case "https":
            return .https
        default:
            return .http
        }
    }

    private static func isSSLIntercepted(_ transaction: RockxyCapturedTransaction) -> Bool {
        transaction.request.url.scheme?.lowercased() == "https"
            && transaction.request.method.uppercased() != "CONNECT"
            && !transaction.isTLSFailure
    }

    private static func errorDescription(for transaction: RockxyCapturedTransaction) -> String? {
        switch transaction.state {
        case .blocked:
            "Blocked by proxy rule"
        case .failed where transaction.isTLSFailure:
            "TLS interception failed; connection was passed through or closed."
        case .failed:
            transaction.response?.statusMessage
        case .pending, .active, .completed:
            nil
        }
    }

    private static func body(from data: Data?, contentType: String?, isTruncated: Bool, limit: Int) -> NetworkBody {
        guard let data, !data.isEmpty else { return .empty }
        let slice = data.prefix(limit)
        let text = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
            ?? "<\(data.count) binary bytes>"
        return NetworkBody(
            bytes: data.count,
            text: text,
            isTruncated: isTruncated || data.count > limit,
            contentType: contentType,
            data: Data(slice)
        )
    }

    private static func webSocketFrame(from frame: RockxyWebSocketFrameSnapshot) -> NetworkWebSocketFrame {
        let payloadText = String(data: frame.payload, encoding: .utf8)
            ?? String(data: frame.payload.prefix(512), encoding: .isoLatin1)
            ?? "<\(frame.payload.count) binary bytes>"
        return NetworkWebSocketFrame(
            id: frame.id,
            timestamp: frame.timestamp,
            direction: frame.direction == .sent ? .sent : .received,
            opcode: frame.opcode,
            payloadText: payloadText,
            payloadBytes: frame.payload.count,
            isFinal: frame.isFinal
        )
    }
}

private enum NetworkReplayError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Replay URL is invalid."
        }
    }
}

private extension NetworkUpstreamProxySettings {
    var rockxyConfiguration: RockxyUpstreamProxyConfiguration {
        RockxyUpstreamProxyConfiguration(
            isEnabled: isEnabled,
            proxies: proxies.map(\.rockxyServer),
            includeHosts: includeHosts,
            excludeHosts: excludeHosts,
            bypassLocalhost: bypassLocalhost,
            dnsOverSocks: dnsOverSocks
        )
    }
}

private extension NetworkUpstreamProxyServerSettings {
    var rockxyServer: RockxyUpstreamProxyServer {
        RockxyUpstreamProxyServer(
            kind: proto.rockxyKind,
            host: host,
            port: port,
            username: username,
            password: password,
            pacScript: pacScript,
            pacURL: pacURL
        )
    }
}

private extension NetworkUpstreamProxyProtocol {
    var rockxyKind: RockxyUpstreamProxyKind {
        switch self {
        case .http:
            .http
        case .https:
            .https
        case .socks5:
            .socks5
        case .pac:
            .pac
        }
    }
}

private extension RockxyProxyRuleSnapshot {
    var networkRule: NetworkRuleDraft {
        NetworkRuleDraft(
            id: id,
            name: name,
            isEnabled: isEnabled,
            urlPattern: urlPattern,
            method: NetworkRuleMatchMethod(rawValue: method.rawValue) ?? .any,
            headerName: headerName ?? "",
            headerValue: headerValue ?? "",
            priority: priority,
            action: action.networkAction,
            lastError: lastError
        )
    }
}

private extension NetworkRuleDraft {
    var rockxyRule: RockxyProxyRuleSnapshot {
        RockxyProxyRuleSnapshot(
            id: id,
            name: name,
            isEnabled: isEnabled,
            urlPattern: urlPattern,
            method: RockxyRuleMatchMethod(rawValue: method.rawValue) ?? .any,
            headerName: headerName.nilIfBlank,
            headerValue: headerValue.nilIfBlank,
            priority: priority,
            action: action.rockxyAction,
            lastError: lastError
        )
    }
}

private extension RockxyRuleActionSnapshot {
    var networkAction: NetworkRuleActionDraft {
        NetworkRuleActionDraft(
            kind: NetworkRuleActionKind(rawValue: kind.rawValue) ?? .block,
            blockStatusCode: blockStatusCode,
            mapLocalPath: mapLocalPath,
            mapLocalStatusCode: mapLocalStatusCode,
            mapLocalIsDirectory: mapLocalIsDirectory,
            mapRemoteScheme: mapRemoteScheme ?? "https",
            mapRemoteHost: mapRemoteHost ?? "",
            mapRemotePortText: mapRemotePort.map(String.init) ?? "",
            mapRemotePath: mapRemotePath ?? "",
            mapRemoteQuery: mapRemoteQuery ?? "",
            mapRemotePreserveHostHeader: mapRemotePreserveHostHeader,
            headerOperations: headerOperations.map(\.networkOperation).nonEmpty(or: [NetworkHeaderOperationDraft()]),
            throttleDelayMs: throttleDelayMs,
            networkConditionName: networkConditionPreset,
            networkConditionDelayMs: networkConditionDelayMs,
            breakpointPhase: NetworkBreakpointPhase(rawValue: breakpointPhase.rawValue) ?? .both,
            scriptMode: NetworkScriptRuleMode(rawValue: scriptMode.rawValue) ?? .transform,
            scriptSource: scriptSource,
            scriptRunOnRequest: scriptRunOnRequest,
            scriptRunOnResponse: scriptRunOnResponse
        )
    }
}

private extension NetworkRuleActionDraft {
    var rockxyAction: RockxyRuleActionSnapshot {
        RockxyRuleActionSnapshot(
            kind: RockxyRuleActionKind(rawValue: kind.rawValue) ?? .block,
            blockStatusCode: blockStatusCode,
            mapLocalPath: mapLocalPath,
            mapLocalStatusCode: mapLocalStatusCode,
            mapLocalIsDirectory: mapLocalIsDirectory,
            mapRemoteScheme: mapRemoteScheme.nilIfBlank,
            mapRemoteHost: mapRemoteHost.nilIfBlank,
            mapRemotePort: Int(mapRemotePortText),
            mapRemotePath: mapRemotePath.nilIfBlank,
            mapRemoteQuery: mapRemoteQuery.nilIfBlank,
            mapRemotePreserveHostHeader: mapRemotePreserveHostHeader,
            headerOperations: headerOperations.map(\.rockxyOperation),
            throttleDelayMs: throttleDelayMs,
            networkConditionPreset: networkConditionName,
            networkConditionDelayMs: networkConditionDelayMs,
            breakpointPhase: RockxyBreakpointPhaseSnapshot(rawValue: breakpointPhase.rawValue) ?? .both,
            scriptMode: RockxyScriptRuleMode(rawValue: scriptMode.rawValue) ?? .transform,
            scriptSource: scriptSource,
            scriptRunOnRequest: scriptRunOnRequest,
            scriptRunOnResponse: scriptRunOnResponse
        )
    }
}

private extension RockxyRuleHeaderOperationSnapshot {
    var networkOperation: NetworkHeaderOperationDraft {
        NetworkHeaderOperationDraft(
            id: id,
            kind: NetworkHeaderOperationKind(rawValue: kind.rawValue) ?? .add,
            phase: NetworkHeaderOperationPhase(rawValue: phase.rawValue) ?? .request,
            name: name,
            value: value
        )
    }
}

private extension NetworkHeaderOperationDraft {
    var rockxyOperation: RockxyRuleHeaderOperationSnapshot {
        RockxyRuleHeaderOperationSnapshot(
            id: id,
            kind: RockxyRuleHeaderOperationKind(rawValue: kind.rawValue) ?? .add,
            phase: RockxyRuleHeaderOperationPhase(rawValue: phase.rawValue) ?? .request,
            name: name,
            value: value
        )
    }
}

private extension RockxyBreakpointItemSnapshot {
    var networkBreakpoint: NetworkBreakpointItem {
        NetworkBreakpointItem(
            id: id,
            phase: NetworkBreakpointPhase(rawValue: phase.rawValue) ?? .request,
            method: method,
            url: url,
            headers: headers.map { NetworkHeaderPair(name: $0.name, value: $0.value) },
            body: body,
            statusCode: statusCode,
            createdAt: createdAt
        )
    }
}

private extension NetworkBreakpointItem {
    var rockxyBreakpoint: RockxyBreakpointItemSnapshot {
        RockxyBreakpointItemSnapshot(
            id: id,
            phase: RockxyBreakpointPhaseSnapshot(rawValue: phase.rawValue) ?? .request,
            method: method,
            url: url,
            headers: headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) },
            body: body,
            statusCode: statusCode,
            createdAt: createdAt
        )
    }
}

private extension RockxyPluginSnapshot {
    var networkPlugin: NetworkPluginItem {
        NetworkPluginItem(
            id: id,
            name: name,
            version: version,
            author: author,
            summary: summary,
            bundlePath: bundlePath,
            isEnabled: isEnabled,
            status: NetworkPluginStatus(rawValue: status.rawValue) ?? .disabled,
            statusMessage: statusMessage,
            lastError: lastError,
            configurationFields: configurationFields
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    func nonEmpty(or fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}
