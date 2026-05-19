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
            )
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
            contentType: contentType
        )
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
