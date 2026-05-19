import Foundation
import RockxyBackendEmbed
import Testing
@testable import ClaudeStats

@Suite("Network Debugging")
@MainActor
struct NetworkDebuggingTests {
    @Test("Network sections migrate legacy setup and expose merged primary entries")
    func networkSectionsMigrateLegacySetup() {
        #expect(NetworkSection(storedRawValue: "setup") == .proxy)
        #expect(NetworkSection(storedRawValue: "helper") == .proxy)
        #expect(NetworkSection(storedRawValue: "upstream") == .proxy)
        #expect(NetworkSection(storedRawValue: "missing") == .traffic)
        #expect(NetworkSection.allCases.map(\.title) == [
            "Traffic",
            "Proxy",
            "Certificates",
            "Rules",
        ])
    }

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
            matchedRuleName: "rewrite-host",
            upstreamProxySummary: "HTTP 127.0.0.1:6152",
            upstreamProxyKind: "HTTP"
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
        #expect(flow.upstreamProxy.kind == "HTTP")
        #expect(flow.upstreamProxy.summary == "HTTP 127.0.0.1:6152")
    }

    @Test("Rockxy websocket frames and matched rule metadata map to NetworkFlow")
    func rockxyWebSocketFramesAndRulesMapToNetworkFlow() throws {
        let frameID = UUID()
        let transaction = RockxyCapturedTransaction(
            id: UUID(),
            sequenceNumber: 12,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200),
            measuredDuration: 0.25,
            request: RockxyCapturedRequest(
                method: "GET",
                url: try #require(URL(string: "ws://stream.example.test/socket")),
                httpVersion: "HTTP/1.1",
                headers: [RockxyCapturedHeader(name: "Host", value: "stream.example.test")],
                body: nil,
                contentType: nil
            ),
            response: nil,
            state: .active,
            isTLSFailure: false,
            isWebSocket: true,
            sourcePort: 52_001,
            clientApp: "curl",
            matchedRuleName: "mock-stream",
            matchedRuleActionSummary: "Mock Script",
            matchedRulePattern: "stream.example.test",
            webSocketFrames: [
                RockxyWebSocketFrameSnapshot(
                    id: frameID,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_201),
                    direction: .received,
                    opcode: "text",
                    payload: Data("hello".utf8),
                    isFinal: true
                ),
            ]
        )

        let flow = RockxyNetworkProxyBackend.flow(from: transaction)

        #expect(flow.flowProtocol == .webSocket)
        #expect(flow.matchedRuleName == "mock-stream")
        #expect(flow.matchedRuleSummary == "Mock Script")
        #expect(flow.matchedRulePattern == "stream.example.test")
        #expect(flow.webSocketFrames.count == 1)
        #expect(flow.webSocketFrames.first?.id == frameID)
        #expect(flow.webSocketFrames.first?.direction == .received)
        #expect(flow.webSocketFrames.first?.payloadText == "hello")
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

    @Test("Auto chain uses existing system proxy as Rockxy upstream")
    func autoChainUsesExistingSystemProxyAsUpstream() async throws {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.networkAutoEnableSystemProxyOnStart = true

        let backend = FakeNetworkProxyBackend()
        let systemProxy = FakeSystemProxyService(
            detectedUpstream: NetworkUpstreamProxySettings(
                isEnabled: true,
                proxies: [
                    NetworkUpstreamProxyServerSettings(
                        proto: .http,
                        host: "127.0.0.1",
                        port: 6_152
                    ),
                ],
                includeHosts: [],
                excludeHosts: ["localhost"],
                bypassLocalhost: true,
                dnsOverSocks: true
            )
        )
        let store = NetworkDebuggerStore(
            preferences: preferences,
            proxyBackend: backend,
            systemProxyService: systemProxy
        )

        store.startCapture()
        try await waitFor { store.systemProxyStatus.isEnabled && !store.isSystemProxyWorking }

        let upstreams = await backend.upstreamConfigurations
        #expect(upstreams.last?.summary == "HTTP 127.0.0.1:6152")
        #expect(store.systemProxyStatus.upstreamProxySummary == "HTTP 127.0.0.1:6152")
    }

    @Test("Ask before chain defers system proxy enable")
    func askBeforeChainDefersSystemProxyEnable() async throws {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.networkAskBeforeChainingExistingSystemProxy = true

        let backend = FakeNetworkProxyBackend()
        let systemProxy = FakeSystemProxyService(
            detectedUpstream: NetworkUpstreamProxySettings(
                isEnabled: true,
                proxies: [
                    NetworkUpstreamProxyServerSettings(
                        proto: .socks5,
                        host: "127.0.0.1",
                        port: 6_153
                    ),
                ],
                includeHosts: [],
                excludeHosts: [],
                bypassLocalhost: true,
                dnsOverSocks: true
            )
        )
        let store = NetworkDebuggerStore(
            preferences: preferences,
            proxyBackend: backend,
            systemProxyService: systemProxy
        )

        store.startCapture()
        try await waitFor { store.captureStatus.isListening }
        store.enableSystemProxy()
        try await waitFor { store.upstreamProxyConfirmation != nil && !store.isSystemProxyWorking }

        #expect(await systemProxy.enabledEndpoints.isEmpty)

        store.confirmUpstreamProxyChaining()
        try await waitFor { store.systemProxyStatus.isEnabled && !store.isSystemProxyWorking }

        #expect(await backend.upstreamConfigurations.last?.summary == "SOCKS5 127.0.0.1:6153")
        #expect(await systemProxy.enabledEndpoints == [FakeNetworkProxyBackend.defaultEndpoint])
    }

    @Test("System proxy snapshot prefers PAC SOCKS then HTTP upstream")
    func systemProxySnapshotBuildsUpstreamCandidate() {
        let endpoint = FakeNetworkProxyBackend.defaultEndpoint
        let snapshot = NetworkSystemProxySnapshot(services: [
            NetworkServiceProxySnapshot(
                serviceName: "Wi-Fi",
                web: NetworkProxyComponentSnapshot(
                    isEnabled: true,
                    server: "127.0.0.1",
                    port: 6_152,
                    authenticated: false
                ),
                secureWeb: NetworkProxyComponentSnapshot(isEnabled: false, server: "", port: nil, authenticated: false),
                socks: NetworkProxyComponentSnapshot(isEnabled: false, server: "", port: nil, authenticated: false),
                autoProxyURL: nil,
                autoProxyEnabled: false,
                bypassDomains: ["*.local"]
            ),
        ])

        let settings = snapshot.upstreamProxy(excluding: endpoint)

        #expect(settings?.summary == "HTTP 127.0.0.1:6152")
        #expect(settings?.excludeHosts == ["*.local"])
    }

    @Test("Traffic filters compose favorites apps domains methods status and protocols")
    func trafficFiltersCompose() {
        let firstID = UUID()
        let secondID = UUID()
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService()
        )
        store.flows = [
            makeFlow(
                id: firstID,
                number: 1,
                clientName: "curl",
                method: "GET",
                url: "https://api.example.test/v1/messages",
                protocol: .https,
                statusCode: 200,
                isPinned: true
            ),
            makeFlow(
                id: secondID,
                number: 2,
                clientName: "Google Chrome",
                method: "POST",
                url: "http://docs.example.test/form",
                protocol: .http,
                statusCode: 404,
                isSaved: true
            ),
            makeFlow(
                number: 3,
                clientName: "curl",
                method: "GET",
                url: "ws://api.example.test/socket",
                protocol: .webSocket,
                statusCode: nil,
                state: .active
            ),
        ]

        #expect(store.trafficApps.first { $0.id == "curl" }?.count == 2)
        #expect(store.trafficDomains.first { $0.id == "api.example.test" }?.count == 2)
        #expect(store.trafficMethods.first { $0.id == "GET" }?.count == 2)
        #expect(store.statusCount(for: .success) == 1)
        #expect(store.statusCount(for: .clientError) == 1)
        #expect(store.protocolCount(for: .webSocket) == 1)
        #expect(store.pinnedTrafficCount == 1)
        #expect(store.savedTrafficCount == 1)

        store.toggleAppFilter("curl")
        store.toggleDomainFilter("api.example.test")
        store.toggleMethodFilter("GET")
        store.toggleStatusFilter(.success)
        store.toggleProtocolFilter(.https)

        #expect(store.filteredFlows.map(\.id) == [firstID])

        store.resetTrafficFilters()
        store.toggleSavedFilter()
        #expect(store.filteredFlows.map(\.id) == [secondID])
    }

    @Test("Request operation service exports cURL HAR and imports cURL")
    func requestOperationServiceExportsAndImports() throws {
        let service = NetworkRequestOperationService()
        let flow = makeFlow(
            number: 9,
            clientName: "curl",
            method: "POST",
            url: "https://api.example.test/messages?debug=1",
            protocol: .https,
            statusCode: 201
        )

        let curl = service.export(flow, format: .curl)
        let har = service.export(flow, format: .har)
        let imported = try service.importRequest(
            "curl -X PATCH -H 'Content-Type: application/json' --data-raw '{\"ok\":true}' https://api.example.test/v1",
            format: .curl
        )

        #expect(curl.contains("curl -X 'POST'"))
        #expect(har.contains("\"version\" : \"1.2\""))
        #expect(imported.draft.method == "PATCH")
        #expect(imported.draft.url == "https://api.example.test/v1")
        #expect(imported.draft.contentType == "application/json")
        #expect(imported.draft.bodyText == "{\"ok\":true}")
    }

    @Test("Store builds WebSocket sessions and filters messages")
    func webSocketSessionsAndFilters() {
        let flowID = UUID()
        let sentID = UUID()
        let receivedID = UUID()
        var flow = makeFlow(
            id: flowID,
            number: 4,
            clientName: "Chrome",
            method: "GET",
            url: "wss://stream.example.test/socket",
            protocol: .webSocket,
            statusCode: nil,
            state: .active
        )
        flow.webSocketFrames = [
            NetworkWebSocketFrame(
                id: sentID,
                timestamp: Date(timeIntervalSince1970: 1_700_000_010),
                direction: .sent,
                opcode: "text",
                payloadText: #"{"type":"subscribe"}"#,
                payloadBytes: 20,
                isFinal: true
            ),
            NetworkWebSocketFrame(
                id: receivedID,
                timestamp: Date(timeIntervalSince1970: 1_700_000_011),
                direction: .received,
                opcode: "binary",
                payloadText: "payload",
                payloadBytes: 7,
                isFinal: true
            ),
        ]
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService()
        )
        store.flows = [flow]
        store.selectWebSocketSession(try! #require(store.webSocketSessions.first))

        #expect(store.webSocketSessions.first?.sentCount == 1)
        #expect(store.webSocketSessions.first?.receivedCount == 1)

        store.webSocketFilter.direction = .received
        #expect(store.filteredWebSocketMessages.map(\.id) == [receivedID])

        store.webSocketFilter.direction = .all
        store.webSocketFilter.opcode = .text
        #expect(store.filteredWebSocketMessages.map(\.id) == [sentID])

        store.webSocketFilter.opcode = .all
        store.webSocketFilter.query = "subscribe"
        #expect(store.filteredWebSocketMessages.map(\.id) == [sentID])
    }

    @Test("Replay and automate insert tagged flow results")
    func replayAndAutomateInsertTaggedFlows() async throws {
        let backend = FakeNetworkProxyBackend()
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: backend,
            systemProxyService: FakeSystemProxyService()
        )
        let flow = makeFlow(
            number: 8,
            clientName: "curl",
            method: "GET",
            url: "https://api.example.test/{{value}}",
            protocol: .https,
            statusCode: 200
        )

        store.prepareReplay(for: flow)
        #expect(store.selectedTrafficWorkspace == .replay)
        store.performReplay()
        try await waitFor { !store.isReplayWorking && !store.flows.isEmpty }
        #expect(store.flows.first?.operationSource == .replay)
        #expect(store.replaySessions.first?.results.count == 1)

        store.sendFlowToAutomate(flow)
        store.automateDraft?.variables = [NetworkAutomateVariable(name: "value", valuesText: "a\nb")]
        store.runAutomate()
        try await waitFor { !store.isAutomateWorking && store.automateResults.count == 2 }
        #expect(store.automateResults.map(\.statusCode) == [200, 200])
        #expect(store.flows.prefix(2).allSatisfy { $0.operationSource == .automate })
    }

    @Test("Upstream environments create manual and detected profiles")
    func upstreamEnvironmentsCreateProfiles() async throws {
        let detected = NetworkUpstreamProxySettings(
            isEnabled: true,
            proxies: [NetworkUpstreamProxyServerSettings(proto: .socks5, host: "127.0.0.1", port: 6_153)],
            includeHosts: [],
            excludeHosts: [],
            bypassLocalhost: true,
            dnsOverSocks: true
        )
        let preferences = Preferences(defaults: makeDefaults())
        let store = NetworkDebuggerStore(
            preferences: preferences,
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService(detectedUpstream: detected)
        )
        store.manualUpstreamProxyHost = "127.0.0.1"
        store.manualUpstreamProxyPortText = "6152"
        store.createManualUpstreamProfileFromCurrentFields()

        #expect(store.selectedUpstreamEnvironment.profiles.contains { $0.summary == "HTTP 127.0.0.1:6152" })

        store.captureStatus = .listening(FakeNetworkProxyBackend.defaultEndpoint)
        store.saveDetectedSystemProxyAsProfile()
        try await waitFor { store.selectedUpstreamEnvironment.profiles.contains { $0.summary == "SOCKS5 127.0.0.1:6153" } }
    }

    @Test("Upstream route rules can be edited and reordered")
    func upstreamRouteRulesCanBeEditedAndReordered() {
        let preferences = Preferences(defaults: makeDefaults())
        let store = NetworkDebuggerStore(
            preferences: preferences,
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService()
        )

        store.createUpstreamRouteRule()
        store.updateSelectedUpstreamRouteRule {
            $0.hostPattern = "*.internal.test"
            $0.scheme = .https
            $0.bypassLocalhost = false
        }
        store.createUpstreamRouteRule()
        let firstRuleID = try! #require(store.selectedUpstreamEnvironment.routeRules.first?.id)
        store.moveSelectedUpstreamRouteRule(offset: -1)

        #expect(store.selectedUpstreamEnvironment.routeRules.count == 2)
        #expect(store.selectedUpstreamEnvironment.routeRules.first?.id != firstRuleID)
        #expect(store.selectedUpstreamEnvironment.routeRules.last?.hostPattern == "*.internal.test")
        #expect(store.selectedUpstreamEnvironment.routeRules.last?.scheme == .https)
        #expect(store.selectedUpstreamEnvironment.routeRules.last?.bypassLocalhost == false)

        store.deleteSelectedUpstreamRouteRule()
        #expect(store.selectedUpstreamEnvironment.routeRules.count == 1)
    }

    @Test("Flow operations add comments prefill rules and delete flows")
    func flowOperationsCommentPrefillRulesAndDelete() {
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService()
        )
        let flow = makeFlow(
            number: 42,
            clientName: "curl",
            method: "POST",
            url: "https://api.example.test/v1/messages",
            protocol: .https,
            statusCode: 201
        )
        store.flows = [flow]

        store.setComment(for: flow.id, text: "needs replay")
        store.createRule(from: flow, kind: .breakpoint)

        #expect(store.flows.first?.comment == "needs replay")
        #expect(store.selectedRule?.action.kind == .breakpoint)
        #expect(store.selectedRule?.method == .post)
        #expect(store.selectedRule?.urlPattern.contains("api\\.example\\.test") == true)

        store.deleteFlow(flow.id)
        #expect(store.flows.isEmpty)
        #expect(store.selectedFlowID == nil)
    }

    @Test("Helper snapshot maps to network helper state")
    func helperSnapshotMapsToNetworkHelperState() {
        let snapshot = makeHelperSnapshot(
            status: .unreachable,
            action: .retry,
            isReachable: false,
            lastErrorMessage: "Connection failed",
            statusMessage: "Helper unreachable",
            canUsePrivilegedHelper: false
        )

        let state = NetworkDebuggerStore.helperState(from: snapshot)

        #expect(state.statusMessage == "Helper unreachable")
        #expect(state.detailMessage == "Connection failed")
        #expect(state.action == .retry)
        #expect(state.isReachable == false)
        #expect(state.canUsePrivilegedHelper == false)
        #expect(state.registrationStatus == "registered")
        #expect(state.installedVersion == "0.7.0")
        #expect(state.bundledVersion == "0.7.1")
        #expect(state.expectedProtocolVersion == 1)
    }

    @Test("Registered helper snapshot maps to check action")
    func registeredHelperSnapshotMapsToCheckAction() {
        let snapshot = makeHelperSnapshot(
            status: .registered,
            action: .check,
            statusMessage: "Helper registered"
        )

        let state = NetworkDebuggerStore.helperState(from: snapshot)

        #expect(state.statusMessage == "Helper registered")
        #expect(state.action == .check)
        #expect(state.isReachable == false)
        #expect(state.canUsePrivilegedHelper == false)
    }

    @Test("Passive helper refresh does not actively probe until check action")
    func passiveHelperRefreshDoesNotActivelyProbeUntilCheckAction() async throws {
        let helper = FakeHelperController(
            passiveSnapshot: makeHelperSnapshot(
                status: .registered,
                action: .check,
                statusMessage: "Helper registered"
            ),
            activeSnapshot: makeHelperSnapshot(
                status: .installedCompatible,
                action: nil,
                isReachable: true,
                statusMessage: "Helper installed",
                canUsePrivilegedHelper: true
            )
        )
        let store = NetworkDebuggerStore(
            preferences: Preferences(defaults: makeDefaults()),
            proxyBackend: FakeNetworkProxyBackend(),
            systemProxyService: FakeSystemProxyService(),
            helperController: helper
        )

        store.refreshPassiveHelperStatus()

        #expect(helper.passiveRefreshCount == 1)
        #expect(helper.activeRefreshCount == 0)
        #expect(store.helperState.action == .check)

        store.performHelperAction()
        try await waitFor { helper.activeRefreshCount == 1 && !store.isHelperWorking }

        #expect(helper.passiveRefreshCount == 1)
        #expect(store.helperState.statusMessage == "Helper installed")
        #expect(store.helperState.canUsePrivilegedHelper == true)
    }

    @Test("Rockxy certificate snapshot preserves local certificate UI state")
    func certificateSnapshotMapsToNetworkCertificateState() {
        let current = NetworkCertificateState(
            rootCAPath: "/old/rootCA.pem",
            isTrusted: false,
            isMITMEnabled: true,
            sslHostAllowlist: ["api.example.test"],
            statusMessage: nil
        )
        let snapshot = RockxyCertificateSnapshot(
            rootCAPath: "/tmp/rockxy/rootCA.pem",
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: false,
            isSystemTrustValidated: true,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: "AA:BB",
            commonName: "Rockxy Root CA",
            lastValidationErrorMessage: nil
        )

        let state = NetworkCertificateService.state(
            from: snapshot,
            preserving: current,
            statusMessage: "Root CA trusted."
        )

        #expect(state.rootCAPath == "/tmp/rockxy/rootCA.pem")
        #expect(state.isTrusted == true)
        #expect(state.isMITMEnabled == true)
        #expect(state.sslHostAllowlist == ["api.example.test"])
        #expect(state.statusMessage == "Root CA trusted.")
    }

    @Test("Certificate validation error overrides success status message")
    func certificateValidationErrorOverridesStatusMessage() {
        let snapshot = RockxyCertificateSnapshot(
            rootCAPath: "/tmp/rockxy/rootCA.pem",
            hasGeneratedCertificate: true,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: "Trust validation failed"
        )

        let state = NetworkCertificateService.state(
            from: snapshot,
            preserving: .empty,
            statusMessage: "Root CA trusted."
        )

        #expect(state.isTrusted == false)
        #expect(state.statusMessage == "Trust validation failed")
    }

    @Test("LaunchDaemon plist uses ClaudeStats Rockxy helper identity")
    func launchDaemonPlistUsesClaudeStatsIdentity() throws {
        let data = try RockxyHelperLaunchDaemonPlist.data(
            machServiceName: "com.claudestats.rockxy.helper",
            bundleProgram: "Contents/Library/HelperTools/RockxyHelperTool",
            allowedCallerIdentifiers: ["com.claudestats.ClaudeStats"]
        )
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let plist = try #require(object as? [String: Any])

        #expect(plist["Label"] as? String == "com.claudestats.rockxy.helper")
        #expect(plist["BundleProgram"] as? String == "Contents/Library/HelperTools/RockxyHelperTool")
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == ["com.claudestats.ClaudeStats"])
        #expect(plist["RunAtLoad"] == nil)
        #expect(plist["KeepAlive"] == nil)

        let machServices = try #require(plist["MachServices"] as? [String: Bool])
        #expect(machServices["com.claudestats.rockxy.helper"] == true)
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

    private func makeFlow(
        id: UUID = UUID(),
        number: Int = 1,
        clientName: String,
        method: String,
        url: String,
        protocol flowProtocol: NetworkFlowProtocol,
        statusCode: Int?,
        state: NetworkFlowState = .completed,
        isPinned: Bool = false,
        isSaved: Bool = false
    ) -> NetworkFlow {
        NetworkFlow(
            id: id,
            number: number,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(number)),
            completedAt: state == .completed ? Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(number) + 0.1) : nil,
            clientName: clientName,
            flowProtocol: flowProtocol,
            state: state,
            request: NetworkRequestCapture(
                method: method,
                url: url,
                httpVersion: "HTTP/1.1",
                headers: [],
                body: .empty
            ),
            response: NetworkResponseCapture(statusCode: statusCode, reason: "", headers: [], body: .empty),
            requestBytes: 0,
            responseBytes: 0,
            isSSLIntercepted: false,
            isEdited: false,
            errorDescription: nil,
            isPinned: isPinned,
            isSaved: isSaved
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

    private func makeHelperSnapshot(
        status: RockxyHelperStatus,
        action: RockxyHelperAction?,
        isReachable: Bool = false,
        lastErrorMessage: String? = nil,
        statusMessage: String,
        canUsePrivilegedHelper: Bool = false
    ) -> RockxyHelperSnapshot {
        RockxyHelperSnapshot(
            status: status,
            action: action,
            isReachable: isReachable,
            registrationStatus: "registered",
            installedVersion: "0.7.0",
            installedBuild: 6,
            installedProtocolVersion: 1,
            bundledVersion: "0.7.1",
            bundledBuild: 7,
            expectedProtocolVersion: 1,
            lastErrorMessage: lastErrorMessage,
            statusMessage: statusMessage,
            canUsePrivilegedHelper: canUsePrivilegedHelper
        )
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
    private(set) var upstreamConfigurations: [NetworkUpstreamProxySettings] = []
    private(set) var replayedDrafts: [NetworkReplayDraft] = []

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

    func updateUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async {
        upstreamConfigurations.append(configuration)
    }

    func testUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async -> NetworkUpstreamProxyTestResult {
        NetworkUpstreamProxyTestResult(
            isReachable: true,
            routeSummary: configuration.summary,
            errorMessage: nil
        )
    }

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow {
        replayedDrafts.append(draft)
        var flow = NetworkFlow(
            id: UUID(),
            number: replayedDrafts.count,
            createdAt: Date(timeIntervalSince1970: 1_700_010_000 + TimeInterval(replayedDrafts.count)),
            completedAt: Date(timeIntervalSince1970: 1_700_010_000 + TimeInterval(replayedDrafts.count) + 0.12),
            clientName: "Replay",
            flowProtocol: .https,
            state: .completed,
            request: NetworkRequestCapture(
                method: draft.method,
                url: draft.url,
                httpVersion: "HTTP/1.1",
                headers: draft.headers,
                body: NetworkBody(
                    bytes: draft.bodyText.utf8.count,
                    text: draft.bodyText,
                    isTruncated: false,
                    contentType: draft.contentType
                )
            ),
            response: NetworkResponseCapture(
                statusCode: 200,
                reason: "OK",
                headers: [NetworkHeaderPair(name: "Content-Type", value: "text/plain")],
                body: NetworkBody(bytes: 2, text: "OK", isTruncated: false, contentType: "text/plain")
            ),
            requestBytes: draft.bodyText.utf8.count,
            responseBytes: 2,
            isSSLIntercepted: true,
            isEdited: false,
            errorDescription: nil
        )
        flow.operationSource = .replay
        flow.isReplay = true
        return flow
    }

    func batchReplay(_ drafts: [NetworkReplayDraft], concurrencyLimit _: Int) async -> [NetworkBatchReplayItemResult] {
        var results: [NetworkBatchReplayItemResult] = []
        for (index, draft) in drafts.enumerated() {
            do {
                var flow = try await replay(draft)
                flow.operationSource = .automate
                results.append(NetworkBatchReplayItemResult(index: index, flow: flow, errorMessage: nil))
            } catch {
                results.append(NetworkBatchReplayItemResult(index: index, flow: nil, errorMessage: error.localizedDescription))
            }
        }
        return results
    }
}

private actor FakeSystemProxyService: NetworkSystemProxyManaging {
    private(set) var enabledEndpoints: [NetworkProxyEndpoint] = []
    private(set) var disabledServices: [[String]] = []
    private let detectedUpstream: NetworkUpstreamProxySettings?

    init(detectedUpstream: NetworkUpstreamProxySettings? = nil) {
        self.detectedUpstream = detectedUpstream
    }

    func detectedUpstreamProxy(excluding _: NetworkProxyEndpoint) async throws -> NetworkUpstreamProxySettings? {
        detectedUpstream
    }

    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus {
        enabledEndpoints.append(endpoint)
        return NetworkSystemProxyStatus(isEnabled: true, managedServices: ["Wi-Fi"], lastError: nil)
    }

    func disable(services: [String]) async throws -> NetworkSystemProxyStatus {
        disabledServices.append(services)
        return .idle
    }
}

@MainActor
private final class FakeHelperController: NetworkHelperManaging {
    private let passiveSnapshot: RockxyHelperSnapshot
    private let activeSnapshot: RockxyHelperSnapshot
    private(set) var passiveRefreshCount = 0
    private(set) var activeRefreshCount = 0

    init(
        passiveSnapshot: RockxyHelperSnapshot,
        activeSnapshot: RockxyHelperSnapshot
    ) {
        self.passiveSnapshot = passiveSnapshot
        self.activeSnapshot = activeSnapshot
    }

    func refreshPassiveStatus() -> RockxyHelperSnapshot {
        passiveRefreshCount += 1
        return passiveSnapshot
    }

    func refreshStatus() async -> RockxyHelperSnapshot {
        activeRefreshCount += 1
        return activeSnapshot
    }

    func install() async throws -> RockxyHelperSnapshot {
        activeSnapshot
    }

    func update() async throws -> RockxyHelperSnapshot {
        activeSnapshot
    }

    func retryConnection() async -> RockxyHelperSnapshot {
        activeSnapshot
    }

    func reinstall() async throws -> RockxyHelperSnapshot {
        activeSnapshot
    }

    func openSystemSettingsLoginItems() {}
}
