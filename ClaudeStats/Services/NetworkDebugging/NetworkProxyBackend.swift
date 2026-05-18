import Foundation

protocol NetworkProxyBackend: Sendable {
    typealias EventHandler = @Sendable (NetworkProxyEvent) -> Void

    func start(
        preferredPorts: ClosedRange<UInt16>,
        eventHandler: @escaping EventHandler
    ) async throws -> NetworkProxyEndpoint

    func stop() async
}
