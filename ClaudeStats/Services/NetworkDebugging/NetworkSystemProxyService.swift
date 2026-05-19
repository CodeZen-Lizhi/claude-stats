import Foundation
import RockxyBackendEmbed

struct NetworkSystemProxyService: NetworkSystemProxyManaging, Sendable {
    private static let helperManagedService = "Rockxy Helper"
    private let direct = DirectNetworkSystemProxyService()

    func detectedUpstreamProxy(excluding endpoint: NetworkProxyEndpoint) async throws -> NetworkUpstreamProxySettings? {
        var settings = try await direct.snapshot().upstreamProxy(excluding: endpoint)
        if let firstPACIndex = settings?.proxies.firstIndex(where: { $0.proto == .pac }) {
            let pacURL = settings?.proxies[firstPACIndex].pacURL
            let pacScript = try? await direct.loadPACScript(from: pacURL)
            settings?.proxies[firstPACIndex].pacScript = pacScript
        }
        return settings
    }

    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus {
        let helper = await RockxyHelperController.shared.refreshStatus()
        if helper.canUsePrivilegedHelper {
            try await RockxyHelperController.shared.overrideSystemProxy(port: endpoint.port)
            return NetworkSystemProxyStatus(
                isEnabled: true,
                managedServices: [Self.helperManagedService],
                lastError: nil
            )
        }
        return try await direct.enable(endpoint: endpoint)
    }

    func disable(services: [String]) async throws -> NetworkSystemProxyStatus {
        if services == [Self.helperManagedService] {
            try await RockxyHelperController.shared.restoreSystemProxy()
            return .idle
        }
        return try await direct.disable(services: services)
    }
}

private actor DirectNetworkSystemProxyService {
    private var restoreSnapshot: NetworkSystemProxySnapshot?

    func snapshot() async throws -> NetworkSystemProxySnapshot {
        try await Task.detached(priority: .userInitiated) {
            try Self.readSnapshot()
        }.value
    }

    func enable(endpoint: NetworkProxyEndpoint) async throws -> NetworkSystemProxyStatus {
        let snapshot = try await Task.detached(priority: .userInitiated) {
            let snapshot = try Self.readSnapshot()
            for service in snapshot.serviceNames {
                try Self.runNetworkSetup(["-setwebproxy", service, endpoint.host, "\(endpoint.port)"])
                try Self.runNetworkSetup(["-setsecurewebproxy", service, endpoint.host, "\(endpoint.port)"])
                try Self.runNetworkSetup(["-setwebproxystate", service, "on"])
                try Self.runNetworkSetup(["-setsecurewebproxystate", service, "on"])
            }
            return snapshot
        }.value
        restoreSnapshot = snapshot
        return NetworkSystemProxyStatus(
            isEnabled: true,
            managedServices: snapshot.serviceNames,
            lastError: nil
        )
    }

    func disable(services: [String]) async throws -> NetworkSystemProxyStatus {
        if let restoreSnapshot {
            self.restoreSnapshot = nil
            try await restore(snapshot: restoreSnapshot)
            return .idle
        }

        try await Task.detached(priority: .userInitiated) {
            let targets = services.isEmpty ? (try Self.networkServices()) : services
            for service in targets {
                try Self.runNetworkSetup(["-setwebproxystate", service, "off"])
                try Self.runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            }
        }.value
        return .idle
    }

    func loadPACScript(from url: URL?) async throws -> String? {
        guard let url else { return nil }
        return try await Task.detached(priority: .utility) {
            if url.isFileURL {
                return try String(contentsOf: url, encoding: .utf8)
            }
            let data = try Data(contentsOf: url)
            return String(data: data, encoding: .utf8)
        }.value
    }

    private func restore(snapshot: NetworkSystemProxySnapshot) async throws {
        try await Task.detached(priority: .userInitiated) {
            for service in snapshot.services {
                try Self.restoreProxy(service.web, serviceName: service.serviceName, setCommand: "-setwebproxy", stateCommand: "-setwebproxystate")
                try Self.restoreProxy(service.secureWeb, serviceName: service.serviceName, setCommand: "-setsecurewebproxy", stateCommand: "-setsecurewebproxystate")
                try Self.restoreProxy(service.socks, serviceName: service.serviceName, setCommand: "-setsocksfirewallproxy", stateCommand: "-setsocksfirewallproxystate")

                if let autoProxyURL = service.autoProxyURL, !autoProxyURL.isEmpty {
                    try Self.runNetworkSetup(["-setautoproxyurl", service.serviceName, autoProxyURL])
                }
                try Self.runNetworkSetup([
                    "-setautoproxystate",
                    service.serviceName,
                    service.autoProxyEnabled ? "on" : "off",
                ])

                if service.bypassDomains.isEmpty {
                    try Self.runNetworkSetup(["-setproxybypassdomains", service.serviceName, "Empty"])
                } else {
                    try Self.runNetworkSetup(["-setproxybypassdomains", service.serviceName] + service.bypassDomains)
                }
            }
        }.value
    }

    private static func restoreProxy(
        _ proxy: NetworkProxyComponentSnapshot,
        serviceName: String,
        setCommand: String,
        stateCommand: String
    ) throws {
        if let port = proxy.port, !proxy.server.isEmpty {
            try runNetworkSetup([setCommand, serviceName, proxy.server, "\(port)"])
        }
        try runNetworkSetup([stateCommand, serviceName, proxy.isEnabled ? "on" : "off"])
    }

    private static func readSnapshot() throws -> NetworkSystemProxySnapshot {
        let services = try networkServices().map { service in
            let autoProxy = try autoProxyURL(service: service)
            return NetworkServiceProxySnapshot(
                serviceName: service,
                web: try proxySnapshot(command: "-getwebproxy", service: service),
                secureWeb: try proxySnapshot(command: "-getsecurewebproxy", service: service),
                socks: try proxySnapshot(command: "-getsocksfirewallproxy", service: service),
                autoProxyURL: autoProxy.url,
                autoProxyEnabled: autoProxy.enabled,
                bypassDomains: try bypassDomains(service: service)
            )
        }
        return NetworkSystemProxySnapshot(services: services)
    }

    private static func proxySnapshot(command: String, service: String) throws -> NetworkProxyComponentSnapshot {
        let output = try runNetworkSetup([command, service])
        return NetworkProxyComponentSnapshot(
            isEnabled: parseBool(linePrefix: "Enabled:", output: output),
            server: parseString(linePrefix: "Server:", output: output) ?? "",
            port: parsePort(linePrefix: "Port:", output: output),
            authenticated: parseBool(linePrefix: "Authenticated Proxy Enabled:", output: output)
        )
    }

    private static func autoProxyURL(service: String) throws -> (url: String?, enabled: Bool) {
        let output = try runNetworkSetup(["-getautoproxyurl", service])
        let url = parseString(linePrefix: "URL:", output: output)
        return (url?.isEmpty == false ? url : nil, parseBool(linePrefix: "Enabled:", output: output))
    }

    private static func bypassDomains(service: String) throws -> [String] {
        let output = try runNetworkSetup(["-getproxybypassdomains", service])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("There aren't any") }
    }

    private static func networkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    private static func parseBool(linePrefix: String, output: String) -> Bool {
        guard let value = parseString(linePrefix: linePrefix, output: output)?.lowercased() else {
            return false
        }
        return value == "yes" || value == "on" || value == "1"
    }

    private static func parsePort(linePrefix: String, output: String) -> UInt16? {
        guard let string = parseString(linePrefix: linePrefix, output: output),
              let value = UInt16(string)
        else {
            return nil
        }
        return value
    }

    private static func parseString(linePrefix: String, output: String) -> String? {
        output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.localizedCaseInsensitiveContains(linePrefix) }?
            .dropFirst(linePrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
