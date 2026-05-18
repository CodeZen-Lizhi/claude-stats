import Foundation
import RockxyBackendEmbed
import Testing
@testable import ClaudeStats

@Suite("Network Debugging")
@MainActor
struct NetworkDebuggingTests {
    @Test("Rockxy transaction maps to NetworkFlow")
    func rockxyTransactionMapsToNetworkFlow() throws {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let transaction = RockxyCapturedTransaction(
            id: id,
            sequenceNumber: 7,
            timestamp: timestamp,
            measuredDuration: 0.125,
            request: RockxyCapturedRequest(
                method: "POST",
                url: try #require(URL(string: "https://api.example.test/v1/messages")),
                httpVersion: "HTTP/1.1",
                headers: [
                    RockxyCapturedHeader(name: "Host", value: "api.example.test"),
                    RockxyCapturedHeader(name: "Content-Type", value: "application/json"),
                ],
                body: Data(#"{"ok":true}"#.utf8),
                contentType: "application/json"
            ),
            response: RockxyCapturedResponse(
                statusCode: 201,
                statusMessage: "Created",
                headers: [RockxyCapturedHeader(name: "Content-Type", value: "text/plain")],
                body: Data("done".utf8),
                bodyTruncated: false,
                contentType: "text/plain"
            ),
            state: .completed,
            isTLSFailure: false,
            isWebSocket: false,
            sourcePort: 52_000,
            clientApp: "curl",
            matchedRuleName: "rewrite-host"
        )

        let flow = RockxyNetworkProxyBackend.flow(from: transaction, bodyLimit: 4)

        #expect(flow.id == id)
        #expect(flow.number == 7)
        #expect(flow.createdAt == timestamp)
        #expect(flow.completedAt == timestamp.addingTimeInterval(0.125))
        #expect(flow.clientName == "curl")
        #expect(flow.flowProtocol == .https)
        #expect(flow.state == .completed)
        #expect(flow.request.method == "POST")
        #expect(flow.request.header(named: "Host") == "api.example.test")
        #expect(flow.request.body.text == #"{"ok"#)
        #expect(flow.request.body.isTruncated == true)
        #expect(flow.response.statusCode == 201)
        #expect(flow.response.reason == "Created")
        #expect(flow.response.body.text == "done")
        #expect(flow.isSSLIntercepted == true)
        #expect(flow.isEdited == true)
        #expect(flow.errorDescription == nil)
    }

    @Test("Rockxy tunnel websocket and blocked states map safely")
    func rockxySpecialCasesMapSafely() throws {
        let tunnel = RockxyNetworkProxyBackend.flow(
            from: makeTransaction(
                method: "CONNECT",
                url: try #require(URL(string: "https://api.example.test:443")),
                state: .completed
            )
        )
        let socket = RockxyNetworkProxyBackend.flow(
            from: makeTransaction(
                method: "GET",
                url: try #require(URL(string: "http://stream.example.test/socket")),
                state: .active,
                isWebSocket: true
            )
        )
        let blocked = RockxyNetworkProxyBackend.flow(
            from: makeTransaction(
                method: "GET",
                url: try #require(URL(string: "http://blocked.example.test")),
                state: .blocked
            )
        )

        #expect(tunnel.flowProtocol == .tunnel)
        #expect(tunnel.isSSLIntercepted == false)
        #expect(socket.flowProtocol == .webSocket)
        #expect(socket.state == .active)
        #expect(blocked.state == .failed)
        #expect(blocked.errorDescription == "Blocked by proxy rule")
    }

    @Test("Store starts and stops proxy backend")
    func storeStartsAndStopsProxyBackend() async throws {
        let backend = FakeNetworkProxyBackend()
        let systemProxy = FakeSystemProxyService()
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: backend,
            systemProxyService: systemProxy
        )

        store.startCapture()
        try await waitFor { store.captureStatus.isListening }

        #expect(await backend.startCallCount == 1)
        #expect(store.listeningEndpoint == FakeNetworkProxyBackend.defaultEndpoint)

        store.stopCapture()
        try await waitFor { store.captureStatus == .stopped }
        try await waitForAsync { await backend.stopCallCount == 1 }

        #expect(await backend.stopCallCount == 1)
        #expect(await systemProxy.enabledEndpoints.isEmpty)
        #expect(await systemProxy.disabledServices.isEmpty)
    }

    @Test("Store reports proxy start errors")
    func storeReportsProxyStartErrors() async throws {
        let backend = FakeNetworkProxyBackend(startError: .portUnavailable)
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: backend,
            systemProxyService: FakeSystemProxyService()
        )

        store.startCapture()
        try await waitFor {
            if case .failed = store.captureStatus { return true }
            return false
        }

        #expect(store.statusMessage == "Port already in use.")
    }

    @Test("Auto system proxy only restores automatically enabled services")
    func autoSystemProxyRestoresOnlyAutomaticEnablement() async throws {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.networkAutoEnableSystemProxyOnStart = true

        let backend = FakeNetworkProxyBackend()
        let systemProxy = FakeSystemProxyService()
        let store = NetworkDebuggerStore(
            preferences: preferences,
            proxyBackend: backend,
            systemProxyService: systemProxy
        )

        store.startCapture()
        try await waitFor { store.systemProxyStatus.isEnabled && !store.isSystemProxyWorking }

        #expect(await systemProxy.enabledEndpoints == [FakeNetworkProxyBackend.defaultEndpoint])

        store.stopCapture()
        try await waitFor { store.systemProxyStatus == .idle && !store.isSystemProxyWorking }

        #expect(await systemProxy.disabledServices == [["Wi-Fi"]])
    }

    @Test("Auto system proxy preference off leaves manual proxy state untouched")
    func autoSystemProxyOffDoesNotTouchSystemProxy() async throws {
        let backend = FakeNetworkProxyBackend()
        let systemProxy = FakeSystemProxyService()
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: backend,
            systemProxyService: systemProxy
        )

        store.startCapture()
        try await waitFor { store.captureStatus.isListening }
        store.stopCapture()
        try await waitFor { store.captureStatus == .stopped }

        #expect(await systemProxy.enabledEndpoints.isEmpty)
        #expect(await systemProxy.disabledServices.isEmpty)
    }

    private func makeTransaction(
        method: String,
        url: URL,
        state: RockxyCapturedTransactionState,
        isWebSocket: Bool = false
    ) -> RockxyCapturedTransaction {
        RockxyCapturedTransaction(
            id: UUID(),
            sequenceNumber: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            measuredDuration: 0.05,
            request: RockxyCapturedRequest(
                method: method,
                url: url,
                httpVersion: "HTTP/1.1",
                headers: [],
                body: nil,
                contentType: nil
            ),
            response: nil,
            state: state,
            isTLSFailure: false,
            isWebSocket: isWebSocket,
            sourcePort: nil,
            clientApp: nil,
            matchedRuleName: nil
        )
    }

    private func waitFor(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0 ..< 100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }

    private func waitForAsync(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0 ..< 100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await predicate())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.claudestats.network.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private enum FakeProxyError: LocalizedError, Sendable {
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .portUnavailable:
            "Port already in use."
        }
    }
}

private actor FakeNetworkProxyBackend: NetworkProxyBackend {
    static let defaultEndpoint = NetworkProxyEndpoint(host: "127.0.0.1", port: 9090)

    private let endpoint: NetworkProxyEndpoint
    private let startError: FakeProxyError?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(
        endpoint: NetworkProxyEndpoint = FakeNetworkProxyBackend.defaultEndpoint,
        startError: FakeProxyError? = nil
    ) {
        self.endpoint = endpoint
        self.startError = startError
    }

    func start(
        preferredPorts _: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> NetworkProxyEndpoint {
        startCallCount += 1
        if let startError {
            throw startError
        }
        eventHandler(.started(endpoint))
        return endpoint
    }

    func stop() async {
        stopCallCount += 1
    }
}

private actor FakeSystemProxyService: NetworkSystemProxyManaging {
    private(set) var enabledEndpoints: [NetworkProxyEndpoint] = []
    private(set) var disabledServices: [[String]] = []

    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus {
        enabledEndpoints.append(endpoint)
        return NetworkSystemProxyStatus(isEnabled: true, managedServices: ["Wi-Fi"], lastError: nil)
    }

    func disable(services: [String]) async throws -> NetworkSystemProxyStatus {
        disabledServices.append(services)
        return .idle
    }
}
