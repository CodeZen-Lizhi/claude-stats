import Foundation

struct NetworkSystemProxyService: NetworkSystemProxyManaging, Sendable {
    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus {
        try await Task.detached(priority: .userInitiated) {
            let services = try Self.networkServices()
            var managed: [String] = []
            for service in services {
                try Self.runNetworkSetup(["-setwebproxy", service, endpoint.host, "\(endpoint.port)"])
                try Self.runNetworkSetup(["-setsecurewebproxy", service, endpoint.host, "\(endpoint.port)"])
                try Self.runNetworkSetup(["-setwebproxystate", service, "on"])
                try Self.runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                managed.append(service)
            }
            return NetworkSystemProxyStatus(isEnabled: true, managedServices: managed, lastError: nil)
        }.value
    }

    func disable(services: [String]) async throws -> NetworkSystemProxyStatus {
        try await Task.detached(priority: .userInitiated) {
            let targets = services.isEmpty ? (try Self.networkServices()) : services
            for service in targets {
                try Self.runNetworkSetup(["-setwebproxystate", service, "off"])
                try Self.runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            }
            return NetworkSystemProxyStatus(isEnabled: false, managedServices: [], lastError: nil)
        }.value
    }

    private static func networkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NetworkSystemProxyError.commandFailed(err.isEmpty ? out : err)
        }
        return out
    }
}

private enum NetworkSystemProxyError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "networksetup failed."
                : message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
