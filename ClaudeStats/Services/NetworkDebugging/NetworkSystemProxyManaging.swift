import Foundation

protocol NetworkSystemProxyManaging: Sendable {
    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus
    func disable(services: [String]) async throws -> NetworkSystemProxyStatus
}
