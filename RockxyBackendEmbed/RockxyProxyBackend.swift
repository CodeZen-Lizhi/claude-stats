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
