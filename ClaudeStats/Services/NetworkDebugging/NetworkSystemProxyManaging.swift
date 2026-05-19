import Foundation

protocol NetworkSystemProxyManaging: Sendable {
    func detectedUpstreamProxy(excluding endpoint: NetworkProxyEndpoint) async throws -> NetworkUpstreamProxySettings?
    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus
    func disable(services: [String]) async throws -> NetworkSystemProxyStatus
}
