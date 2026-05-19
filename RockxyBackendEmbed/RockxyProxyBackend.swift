import Foundation

public actor RockxyProxyBackend {
    public typealias EventHandler = @Sendable (RockxyProxyBackendEvent) -> Void

    private var proxyServer: ProxyServer?
    private var eventHandler: EventHandler?
    private let sequenceCounter = RockxySequenceCounter()

    public init() {}

    @discardableResult
    public func start(
        preferredPorts: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> RockxyProxyEndpoint {
        await stop()
        self.eventHandler = eventHandler
        sequenceCounter.reset()

        var lastError: Error?
        for port in preferredPorts {
            do {
                return try await start(on: port, eventHandler: eventHandler)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? RockxyProxyBackendError.noAvailablePort
    }

    public func stop() async {
        guard let server = proxyServer else {
            eventHandler?(.stopped)
            return
        }
        proxyServer = nil
        await server.stop()
        eventHandler?(.stopped)
    }

    public func updateUpstreamProxy(_ configuration: RockxyUpstreamProxyConfiguration) async {
        guard let server = proxyServer else { return }
        await server.updateUpstreamProxy(configuration.internalConfiguration)
    }

    public func testUpstreamProxy(
        _ configuration: RockxyUpstreamProxyConfiguration,
        targetHost: String = "example.com",
        targetPort: UInt16 = 443,
        scheme: String = "https"
    ) async -> RockxyUpstreamProxyTestResult {
        do {
            let internalConfiguration = configuration.internalConfiguration
            let routes = try UpstreamRouter(configuration: internalConfiguration)
                .routes(for: targetHost, port: Int(targetPort), scheme: scheme)
            let summary = routes.map(\.summary).joined(separator: " -> ")
            let isReachable = !routes.contains {
                if case .failed = $0 { return true }
                return false
            }
            return RockxyUpstreamProxyTestResult(
                isReachable: isReachable,
                routeSummary: summary.isEmpty ? "Direct" : summary,
                errorMessage: nil
            )
        } catch {
            return RockxyUpstreamProxyTestResult(
                isReachable: false,
                routeSummary: "Failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func start(on port: UInt16, eventHandler: @escaping EventHandler) async throws -> RockxyProxyEndpoint {
        let endpoint = RockxyProxyEndpoint(host: "127.0.0.1", port: port)
        let sequenceCounter = sequenceCounter
        let server = ProxyServer(
            configuration: ProxyConfiguration(port: Int(port), listenAddress: endpoint.host, listenIPv6: false),
            certificateManager: .shared,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            onTransactionComplete: { transaction in
                let captured = RockxyTransactionMapper.captured(
                    from: transaction,
                    sequenceNumber: sequenceCounter.next()
                )
                eventHandler(.transaction(captured))
            }
        )

        do {
            try await server.start()
            proxyServer = server
            eventHandler(.started(endpoint))
            return endpoint
        } catch {
            await server.stop()
            if error is ProxyServerError {
                throw error
            }
            eventHandler(.failed(error.localizedDescription))
            throw error
        }
    }
}

private extension RockxyUpstreamProxyConfiguration {
    var internalConfiguration: UpstreamProxyConfiguration {
        UpstreamProxyConfiguration(
            isEnabled: isEnabled,
            proxies: proxies.map(\.internalServer),
            includeHosts: includeHosts,
            excludeHosts: excludeHosts,
            bypassLocalhost: bypassLocalhost,
            dnsOverSocks: dnsOverSocks,
            listenerHost: "127.0.0.1",
            listenerPort: 9_090
        )
    }
}

private extension RockxyUpstreamProxyServer {
    var internalServer: UpstreamProxyServer {
        UpstreamProxyServer(
            kind: kind.internalKind,
            host: host,
            port: Int(port),
            username: username,
            password: password,
            pacScript: pacScript,
            pacURL: pacURL
        )
    }
}

private extension RockxyUpstreamProxyKind {
    var internalKind: UpstreamProxyKind {
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

private final class RockxySequenceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }
}
