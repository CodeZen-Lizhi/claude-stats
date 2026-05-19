import Foundation

protocol NetworkProxyBackend: Sendable {
    typealias EventHandler = @Sendable (NetworkProxyEvent) -> Void

    func start(
        preferredPorts: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> NetworkProxyEndpoint

    func stop() async

    func updateUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async

    func testUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async -> NetworkUpstreamProxyTestResult

    func rules() async -> [NetworkRuleDraft]

    func saveRule(_ rule: NetworkRuleDraft) async throws

    func deleteRule(id: UUID) async throws

    func setRuleEnabled(id: UUID, enabled: Bool) async throws

    func moveRule(id: UUID, before destinationID: UUID?) async throws

    func testRule(_ rule: NetworkRuleDraft, sampleURL: URL, method: String, headers: [NetworkHeaderPair]) async -> NetworkRuleMatchSnapshot

    func exportRulesData() async throws -> Data

    func importRulesData(_ data: Data) async throws

    func plugins() async -> [NetworkPluginItem]

    func installPlugin(at path: String) async throws

    func setPluginEnabled(id: String, enabled: Bool) async throws

    func reloadPlugin(id: String) async throws

    func deletePlugin(id: String) async throws

    func breakpoints() async -> [NetworkBreakpointItem]

    func updateBreakpoint(_ item: NetworkBreakpointItem) async

    func resolveBreakpoint(id: UUID, decision: NetworkBreakpointDecision) async

    func resolveAllBreakpoints(decision: NetworkBreakpointDecision) async

    func compose(_ draft: NetworkReplayDraft) async throws -> NetworkFlow

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow

    func batchReplay(_ drafts: [NetworkReplayDraft], concurrencyLimit: Int) async -> [NetworkBatchReplayItemResult]

    func updateInterceptedFlow(_ item: NetworkBreakpointItem) async

    func forwardInterceptedFlow(id: UUID) async

    func dropInterceptedFlow(id: UUID) async

    func exportFlows(_ flows: [NetworkFlow], format: NetworkRequestExportFormat) async throws -> Data

    func importRequest(_ text: String, format: NetworkRequestImportFormat) async throws -> NetworkReplayDraft

    func sendWebSocketMessage(_ draft: NetworkWebSocketSendDraft) async throws -> NetworkWebSocketMessage
}

extension NetworkProxyBackend {
    func updateUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async {}

    func testUpstreamProxy(_ configuration: NetworkUpstreamProxySettings) async -> NetworkUpstreamProxyTestResult {
        NetworkUpstreamProxyTestResult(
            isReachable: true,
            routeSummary: configuration.summary,
            errorMessage: nil
        )
    }

    func rules() async -> [NetworkRuleDraft] { [] }

    func saveRule(_ rule: NetworkRuleDraft) async throws {}

    func deleteRule(id: UUID) async throws {}

    func setRuleEnabled(id: UUID, enabled: Bool) async throws {}

    func moveRule(id: UUID, before destinationID: UUID?) async throws {}

    func testRule(_ rule: NetworkRuleDraft, sampleURL: URL, method: String, headers: [NetworkHeaderPair]) async -> NetworkRuleMatchSnapshot {
        NetworkRuleMatchSnapshot(matches: false, message: "Rules are not available for this backend.")
    }

    func exportRulesData() async throws -> Data { Data("[]".utf8) }

    func importRulesData(_ data: Data) async throws {}

    func plugins() async -> [NetworkPluginItem] { [] }

    func installPlugin(at path: String) async throws {}

    func setPluginEnabled(id: String, enabled: Bool) async throws {}

    func reloadPlugin(id: String) async throws {}

    func deletePlugin(id: String) async throws {}

    func breakpoints() async -> [NetworkBreakpointItem] { [] }

    func updateBreakpoint(_ item: NetworkBreakpointItem) async {}

    func resolveBreakpoint(id: UUID, decision: NetworkBreakpointDecision) async {}

    func resolveAllBreakpoints(decision: NetworkBreakpointDecision) async {}

    func compose(_ draft: NetworkReplayDraft) async throws -> NetworkFlow {
        var flow = try await replay(draft)
        flow.operationSource = .compose
        return flow
    }

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow {
        throw NetworkProxyBackendDefaultError.unsupportedReplay
    }

    func batchReplay(_ drafts: [NetworkReplayDraft], concurrencyLimit _: Int) async -> [NetworkBatchReplayItemResult] {
        var results: [NetworkBatchReplayItemResult] = []
        for (index, draft) in drafts.enumerated() {
            do {
                results.append(NetworkBatchReplayItemResult(index: index, flow: try await replay(draft), errorMessage: nil))
            } catch {
                results.append(NetworkBatchReplayItemResult(index: index, flow: nil, errorMessage: error.localizedDescription))
            }
        }
        return results
    }

    func updateInterceptedFlow(_ item: NetworkBreakpointItem) async {
        await updateBreakpoint(item)
    }

    func forwardInterceptedFlow(id: UUID) async {
        await resolveBreakpoint(id: id, decision: .execute)
    }

    func dropInterceptedFlow(id: UUID) async {
        await resolveBreakpoint(id: id, decision: .abort)
    }

    func exportFlows(_ flows: [NetworkFlow], format: NetworkRequestExportFormat) async throws -> Data {
        let text = NetworkRequestOperationService().export(flows, format: format)
        return Data(text.utf8)
    }

    func importRequest(_ text: String, format: NetworkRequestImportFormat) async throws -> NetworkReplayDraft {
        try NetworkRequestOperationService().importRequest(text, format: format).draft
    }

    func sendWebSocketMessage(_ draft: NetworkWebSocketSendDraft) async throws -> NetworkWebSocketMessage {
        throw NetworkProxyBackendDefaultError.unsupportedWebSocketSend
    }
}

private enum NetworkProxyBackendDefaultError: LocalizedError {
    case unsupportedReplay
    case unsupportedWebSocketSend

    var errorDescription: String? {
        switch self {
        case .unsupportedReplay:
            "Replay is not available for this backend."
        case .unsupportedWebSocketSend:
            "Sending WebSocket messages is not available for this backend."
        }
    }
}
