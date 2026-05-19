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
}
