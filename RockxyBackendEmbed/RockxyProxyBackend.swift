import Foundation

public actor RockxyProxyBackend {
    public typealias EventHandler = @Sendable (RockxyProxyBackendEvent) -> Void

    private var proxyServer: ProxyServer?
    private var eventHandler: EventHandler?
    private var currentEndpoint: RockxyProxyEndpoint?
    let sequenceCounter = RockxySequenceCounter()
    let ruleEngine = RuleEngine()
    let ruleStore = RuleStore()
    let pluginManager = PluginManager.shared
    var currentUpstreamProxy: RockxyUpstreamProxyConfiguration = .disabled

    public init() {}

    @discardableResult
    public func start(
        preferredPorts: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> RockxyProxyEndpoint {
        await stop()
        self.eventHandler = eventHandler
        sequenceCounter.reset()
        ProcessResolver.shared.invalidateCache()

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
        currentEndpoint = nil
        await server.stop()
        ProcessResolver.shared.invalidateCache()
        eventHandler?(.stopped)
    }

    public func updateUpstreamProxy(_ configuration: RockxyUpstreamProxyConfiguration) async {
        currentUpstreamProxy = configuration
        guard let server = proxyServer else { return }
        await server.updateUpstreamProxy(configuration.internalConfiguration(listenerEndpoint: currentEndpoint))
    }

    public func testUpstreamProxy(
        _ configuration: RockxyUpstreamProxyConfiguration,
        targetHost: String = "example.com",
        targetPort: UInt16 = 443,
        scheme: String = "https"
    ) async -> RockxyUpstreamProxyTestResult {
        do {
            let internalConfiguration = configuration.internalConfiguration(listenerEndpoint: currentEndpoint)
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
        let proxyPort = Int(port)
        try? await ruleEngine.loadRules(from: ruleStore)
        await pluginManager.ensureLoadedOnce()
        let server = ProxyServer(
            configuration: ProxyConfiguration(
                port: Int(port),
                listenAddress: endpoint.host,
                listenIPv6: false,
                upstreamProxy: currentUpstreamProxy.internalConfiguration(listenerEndpoint: endpoint)
            ),
            certificateManager: .shared,
            ruleEngine: ruleEngine,
            scriptPluginManager: pluginManager.scriptManager,
            onTransactionComplete: { transaction in
                let sequenceNumber = sequenceCounter.number(for: transaction.id)
                let captured = RockxyTransactionMapper.captured(from: transaction, sequenceNumber: sequenceNumber)
                eventHandler(.transaction(captured))
                guard transaction.sourcePort != nil else {
                    return
                }
                Task {
                    guard let clientApp = await Self.resolveClientApp(for: transaction, proxyPort: proxyPort) else {
                        return
                    }
                    guard transaction.clientApp != clientApp else {
                        return
                    }
                    transaction.clientApp = clientApp
                    transaction.clientAttribution = .process
                    let enriched = RockxyTransactionMapper.captured(from: transaction, sequenceNumber: sequenceNumber)
                    eventHandler(.transaction(enriched))
                }
            },
            onBreakpointHit: { data in
                await BreakpointManager.shared.enqueueAndWait(data)
            }
        )

        do {
            try await server.start()
            proxyServer = server
            currentEndpoint = endpoint
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

    private nonisolated static func resolveClientApp(
        for transaction: HTTPTransaction,
        proxyPort: Int
    ) async -> String? {
        guard let sourcePort = transaction.sourcePort else {
            return nil
        }
        let portMap = await ProcessResolver.shared.resolveProcessesAsync(proxyPort: proxyPort)
        guard let appName = portMap[sourcePort]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appName.isEmpty
        else {
            return nil
        }
        return appName
    }
}

private extension RockxyUpstreamProxyConfiguration {
    func internalConfiguration(listenerEndpoint: RockxyProxyEndpoint?) -> UpstreamProxyConfiguration {
        UpstreamProxyConfiguration(
            isEnabled: isEnabled,
            proxies: proxies.map(\.internalServer),
            includeHosts: includeHosts,
            excludeHosts: excludeHosts,
            bypassLocalhost: bypassLocalhost,
            dnsOverSocks: dnsOverSocks,
            listenerHost: listenerEndpoint?.host ?? "127.0.0.1",
            listenerPort: Int(listenerEndpoint?.port ?? 9_090)
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

final class RockxySequenceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var valueByTransactionID: [UUID: Int] = [:]

    func number(for transactionID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = valueByTransactionID[transactionID] {
            return existing
        }
        value += 1
        valueByTransactionID[transactionID] = value
        return value
    }

    func reset() {
        lock.lock()
        value = 0
        valueByTransactionID.removeAll()
        lock.unlock()
    }
}
