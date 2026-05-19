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

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow
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

    func replay(_ draft: NetworkReplayDraft) async throws -> NetworkFlow {
        throw NetworkProxyBackendDefaultError.unsupportedReplay
    }
}

private enum NetworkProxyBackendDefaultError: LocalizedError {
    case unsupportedReplay

    var errorDescription: String? {
        switch self {
        case .unsupportedReplay:
            "Replay is not available for this backend."
        }
    }
}
