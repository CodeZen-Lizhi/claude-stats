import Foundation

struct OpsPortTableRow: Identifiable, Sendable, Hashable {
    var id: String { item.id }

    var item: OpsPortItem
    var pidText: String
    var portText: String
    var processName: String
    var user: String
    var protocolName: String
    var displayAddress: String
    var localhostURL: String
    var commandLine: String
    var executablePath: String?
    var protectionReason: String?
    var searchText: String

    init(item: OpsPortItem) {
        self.item = item
        pidText = "\(item.pid)"
        portText = ":\(item.port)"
        processName = item.processName
        user = item.user.isEmpty ? "--" : item.user
        protocolName = item.protocolName
        displayAddress = item.displayAddress
        localhostURL = item.localhostURL
        commandLine = item.commandLine
        executablePath = item.executablePath
        protectionReason = item.protection.reason
        searchText = [
            item.processName,
            item.user,
            "\(item.port)",
            item.commandLine,
            item.localAddress,
            item.protocolName,
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

struct OpsProcessTableRow: Identifiable, Sendable, Hashable {
    var id: Int32 { item.pid }

    var item: OpsProcessItem
    var pidText: String
    var ppidText: String
    var user: String
    var cpuPercent: Double
    var memoryPercent: Double
    var cpuText: String
    var memoryText: String
    var elapsed: String
    var displayName: String
    var executablePath: String
    var commandLine: String
    var isDeveloperProcess: Bool
    var canRevealExecutable: Bool
    var protectionReason: String?
    var searchText: String
    var sortName: String

    init(item: OpsProcessItem, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.item = item
        pidText = "\(item.pid)"
        ppidText = "\(item.ppid)"
        user = item.user
        cpuPercent = item.cpuPercent
        memoryPercent = item.memoryPercent
        cpuText = String(format: "%.1f", item.cpuPercent)
        memoryText = String(format: "%.1f", item.memoryPercent)
        elapsed = item.elapsed
        executablePath = item.executablePath
        commandLine = item.commandLine

        let executableName = URL(fileURLWithPath: item.executablePath).lastPathComponent
        displayName = executableName.isEmpty
            ? (item.commandLine.split(separator: " ").first.map(String.init) ?? "Process \(item.pid)")
            : executableName

        let normalizedText = "\(displayName) \(item.commandLine)".lowercased()
        isDeveloperProcess = Self.developerMarkers.contains { normalizedText.contains($0) }
        canRevealExecutable = fileExists(item.executablePath)
        protectionReason = item.protection.reason
        searchText = [
            displayName,
            item.user,
            "\(item.pid)",
            item.commandLine,
            item.executablePath,
        ]
        .joined(separator: " ")
        .lowercased()
        sortName = displayName.lowercased()
    }

    private static let developerMarkers: [String] = [
        "node", "vite", "next", "bun", "deno", "python", "ruby",
        "swift", "xcodebuild", "docker", "pnpm", "npm", "yarn",
        "cargo", "go", "gradle", "java", "uvicorn", "rails",
    ]
}
