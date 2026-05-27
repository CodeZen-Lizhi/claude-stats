import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

@MainActor
struct DiagnosticsExporter {
    enum ExportError: LocalizedError {
        case couldNotCreateArchive(String)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateArchive(let message):
                "Could not create diagnostics archive: \(message)"
            }
        }
    }

    func export(environment: AppEnvironment, to archiveURL: URL, now: Date = .now) async throws -> URL {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatisticsDiagnostics-\(Int(now.timeIntervalSince1970))", isDirectory: true)
        try? fileManager.removeItem(at: workDir)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDir) }

        let report = makeReport(environment: environment, now: now)
        try writeJSON(report, to: workDir.appendingPathComponent("diagnostics-summary.json"))
        try report.diagnosisText.write(
            to: workDir.appendingPathComponent("diagnosis.txt"),
            atomically: true,
            encoding: .utf8
        )
        try report.scannerText.write(
            to: workDir.appendingPathComponent("scanner-report.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await recentAppLog().write(
            to: workDir.appendingPathComponent("recent-app.log"),
            atomically: true,
            encoding: .utf8
        )

        try? fileManager.removeItem(at: archiveURL)
        let result = runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", workDir.lastPathComponent, archiveURL.path],
            currentDirectory: workDir.deletingLastPathComponent()
        )
        guard result.exitCode == 0 else {
            throw ExportError.couldNotCreateArchive(result.stderr.nilIfEmpty ?? result.stdout)
        }
        return archiveURL
    }

    func makeReport(environment: AppEnvironment, now: Date = .now) -> DiagnosticsReport {
        let provider = environment.preferences.selectedProvider
        let sessions = environment.store.sessions(for: provider)
        let sessionDirectory = environment.store.dataDirectoryPath(for: provider)
        let usageLimit = environment.usageLimits.report(for: provider)
        let parseFailures = sessions.filter { $0.stats == nil }.count
        let readableSessionDirectory = sessionDirectory.map { FileManager.default.isReadableFile(atPath: $0) } ?? false

        let summary = DiagnosticsSummary(
            generatedAt: now,
            appVersion: appVersionString,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: ProcessInfo.processInfo.machineHardwareName,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier
        )

        let preferences = DiagnosticsPreferences(
            selectedProvider: environment.preferences.selectedProvider.rawValue,
            appearance: environment.preferences.appearancePreference.rawValue,
            language: environment.preferences.appLanguagePreference.rawValue,
            autoRefreshMinutes: environment.preferences.autoRefreshMinutes,
            menuBarMetric: environment.preferences.menuBarMetric.rawValue,
            menuBarPeriod: environment.preferences.menuBarPeriod.rawValue,
            includeCacheInTokens: environment.preferences.includeCacheInTokens,
            gitTrackingEnabled: environment.preferences.gitTrackingEnabled,
            githubEnabled: environment.preferences.githubEnabled,
            systemMonitorEnabled: environment.preferences.systemMonitorEnabled,
            floatingTabEnabled: environment.preferences.floatingTabEnabled
        )

        let scanner = DiagnosticsScannerReport(
            provider: provider.rawValue,
            dataDirectoryExists: environment.store.dataDirectoryExists(for: provider),
            dataDirectoryPath: sessionDirectory.map(Self.redactPath),
            dataDirectoryReadable: readableSessionDirectory,
            visibleSessionCount: sessions.count,
            parsedSessionCount: sessions.filter { $0.stats != nil }.count,
            parseFailureCount: parseFailures,
            projectCount: Set(sessions.map(\.projectDirectoryName)).count,
            lastStoreRefresh: environment.store.lastRefreshedAt,
            newestSessionModifiedAt: sessions.map(\.lastModified).max()
        )

        let integrations = DiagnosticsIntegrations(
            codexHomePath: Self.redactPath(CodexPaths.default.homeDirectory.path),
            codexHomeExists: FileManager.default.fileExists(atPath: CodexPaths.default.homeDirectory.path),
            gitExecutablePath: GitAnalyzer.gitPath,
            gitAvailable: GitCommandRunner().isAvailable,
            githubStatus: Self.githubStatus(environment.github.status),
            openAIStatus: Self.openAIStatus(environment.openAIStatus),
            sparkleUpdaterStarted: true,
            usageLimitStatus: usageLimit?.status.rawValue ?? "not_loaded",
            usageLimitCapturedAt: usageLimit?.lastCapturedAt,
            usageLimitSourcePath: usageLimit?.snapshot?.sourcePath.map(Self.redactPath)
        )

        let permissions = DiagnosticsPermissions(
            accessibilityTrusted: AXIsProcessTrusted(),
            screenRecordingPreflight: CGPreflightScreenCaptureAccess(),
            codexDataReadable: readableSessionDirectory
        )

        return DiagnosticsReport(
            summary: summary,
            preferences: preferences,
            scanner: scanner,
            integrations: integrations,
            permissions: permissions,
            findings: Self.findings(scanner: scanner, integrations: integrations, permissions: permissions)
        )
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(short) (\(build))"
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func recentAppLog() async -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.claudestats.CodexStatistics"
        let predicate = "subsystem == \"\(bundleID)\""
        let result = runProcess(
            executable: "/usr/bin/log",
            arguments: ["show", "--last", "2h", "--style", "compact", "--predicate", predicate],
            timeout: 8
        )
        if result.exitCode == 0, !result.stdout.isEmpty {
            return Self.redactText(result.stdout)
        }
        return [
            "Recent app log unavailable.",
            "exitCode=\(result.exitCode)",
            Self.redactText(result.stderr.nilIfEmpty ?? result.stdout),
        ].joined(separator: "\n")
    }

    private static func findings(
        scanner: DiagnosticsScannerReport,
        integrations: DiagnosticsIntegrations,
        permissions: DiagnosticsPermissions
    ) -> [String] {
        var findings: [String] = []
        if !scanner.dataDirectoryExists {
            findings.append("Codex data directory was not found.")
        } else if !scanner.dataDirectoryReadable {
            findings.append("Codex data directory exists but is not readable; Full Disk Access may be needed.")
        }
        if scanner.visibleSessionCount == 0 {
            findings.append("No visible Codex sessions were parsed.")
        }
        if scanner.parseFailureCount > 0 {
            findings.append("\(scanner.parseFailureCount) sessions did not have parsed stats.")
        }
        if integrations.usageLimitStatus == "cached" {
            findings.append("Usage limit data is cached; wait for a newer Codex response or refresh.")
        } else if integrations.usageLimitStatus == "unavailable" {
            findings.append("Usage limit data is unavailable; inspect scanner and Codex transcript access.")
        }
        if !integrations.gitAvailable {
            findings.append("System git executable is unavailable.")
        }
        if !permissions.accessibilityTrusted {
            findings.append("Accessibility permission is not granted; features that inspect other apps may be limited.")
        }
        if findings.isEmpty {
            findings.append("No obvious local configuration issue was detected.")
        }
        return findings
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval = 20
    ) -> DiagnosticsProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return DiagnosticsProcessResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
        }
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return DiagnosticsProcessResult(stdout: stdoutText, stderr: stderrText, exitCode: process.terminationStatus)
    }

    private static func githubStatus(_ status: GitHubViewModel.Status) -> String {
        switch status {
        case .disconnected:
            "disconnected"
        case .connecting:
            "connecting"
        case .connected(let login, let syncedAt, let isStale):
            "connected(login: \(login), syncedAt: \(syncedAt?.description ?? "never"), stale: \(isStale))"
        case .failed(let reason):
            "failed(\(reason))"
        }
    }

    private static func openAIStatus(_ status: OpenAIStatusViewModel) -> String {
        if let error = status.lastError { return "failed(\(error))" }
        if let snapshot = status.snapshot {
            let severity = snapshot.worstVisibleSeverity.displayName
            return status.isStale ? "cached(\(severity))" : "fresh(\(severity))"
        }
        return status.isLoading ? "loading" : "not_loaded"
    }

    static func redactPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func redactText(_ text: String) -> String {
        var out = text
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        out = out.replacingOccurrences(of: home, with: "~")
        out = out.replacingOccurrences(
            of: #"(?i)(api[_-]?key|token|jwt|authorization|password)[=: ]+[^ \n]+"#,
            with: "$1=<redacted>",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{12,}"#,
            with: "<redacted>",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#,
            with: "<redacted>",
            options: .regularExpression
        )
        return out
    }
}

struct DiagnosticsProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct DiagnosticsReport: Codable, Equatable {
    let summary: DiagnosticsSummary
    let preferences: DiagnosticsPreferences
    let scanner: DiagnosticsScannerReport
    let integrations: DiagnosticsIntegrations
    let permissions: DiagnosticsPermissions
    let findings: [String]

    var diagnosisText: String {
        (["Codex Statistics Diagnostics", ""] + findings.map { "- \($0)" }).joined(separator: "\n")
    }

    var scannerText: String {
        [
            "Provider: \(scanner.provider)",
            "Data directory exists: \(scanner.dataDirectoryExists)",
            "Data directory readable: \(scanner.dataDirectoryReadable)",
            "Data directory: \(scanner.dataDirectoryPath ?? "-")",
            "Visible sessions: \(scanner.visibleSessionCount)",
            "Parsed sessions: \(scanner.parsedSessionCount)",
            "Parse failures: \(scanner.parseFailureCount)",
            "Projects: \(scanner.projectCount)",
            "Last refresh: \(scanner.lastStoreRefresh?.description ?? "-")",
            "Newest session modified: \(scanner.newestSessionModifiedAt?.description ?? "-")",
        ].joined(separator: "\n")
    }
}

struct DiagnosticsSummary: Codable, Equatable {
    let generatedAt: Date
    let appVersion: String
    let bundleIdentifier: String
    let macOSVersion: String
    let architecture: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
}

struct DiagnosticsPreferences: Codable, Equatable {
    let selectedProvider: String
    let appearance: String
    let language: String
    let autoRefreshMinutes: Int
    let menuBarMetric: String
    let menuBarPeriod: String
    let includeCacheInTokens: Bool
    let gitTrackingEnabled: Bool
    let githubEnabled: Bool
    let systemMonitorEnabled: Bool
    let floatingTabEnabled: Bool
}

struct DiagnosticsScannerReport: Codable, Equatable {
    let provider: String
    let dataDirectoryExists: Bool
    let dataDirectoryPath: String?
    let dataDirectoryReadable: Bool
    let visibleSessionCount: Int
    let parsedSessionCount: Int
    let parseFailureCount: Int
    let projectCount: Int
    let lastStoreRefresh: Date?
    let newestSessionModifiedAt: Date?
}

struct DiagnosticsIntegrations: Codable, Equatable {
    let codexHomePath: String
    let codexHomeExists: Bool
    let gitExecutablePath: String
    let gitAvailable: Bool
    let githubStatus: String
    let openAIStatus: String
    let sparkleUpdaterStarted: Bool
    let usageLimitStatus: String
    let usageLimitCapturedAt: Date?
    let usageLimitSourcePath: String?
}

struct DiagnosticsPermissions: Codable, Equatable {
    let accessibilityTrusted: Bool
    let screenRecordingPreflight: Bool
    let codexDataReadable: Bool
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
