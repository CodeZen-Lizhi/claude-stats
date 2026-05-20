import Darwin
import Foundation

protocol OpsServicing: Sendable {
    func loadPorts() async throws -> [OpsPortItem]
    func loadProcesses() async throws -> [OpsProcessItem]
    func loadBrew() async -> OpsBrewSnapshot
    func loadEnvironment() async -> [OpsEnvironmentTool]
    func loadCleanupItems() async -> [OpsCleanupItem]
    func loadDiagnostics() async -> OpsDiagnosticsSnapshot
    func runURLDiagnostics(_ rawURL: String) async -> OpsURLDiagnosticResult
    func terminate(target: OpsProcessIdentity, signal: Int32) async throws -> OpsTerminationOutcome
    func runBrew(action: OpsBrewAction) async throws -> OpsCommandResult
    func cleanup(kinds: Set<OpsCleanupKind>) async throws -> OpsCleanupResult
}

struct OpsService: OpsServicing {
    private let runner: any OpsCommandRunning
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        runner: any OpsCommandRunning = DefaultOpsCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.runner = runner
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func loadPorts() async throws -> [OpsPortItem] {
        async let processList = loadProcesses()
        async let lsof = runRequired(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLPn"],
            timeout: 6
        )
        let processes = try await processList
        let processLookup = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let result = try await lsof
        return OpsParsers.parseLsofFieldOutput(result.stdout, processLookup: processLookup)
    }

    func loadProcesses() async throws -> [OpsProcessItem] {
        let result = try await runRequired(
            executable: "/bin/ps",
            arguments: ["axww", "-o", "pid=,ppid=,user=,pcpu=,pmem=,etime=,lstart=,command="],
            timeout: 6
        )
        return OpsParsers.parseProcessList(
            result.stdout,
            currentPID: Int32(ProcessInfo.processInfo.processIdentifier),
            currentUser: NSUserName()
        )
    }

    func loadBrew() async -> OpsBrewSnapshot {
        guard let brewPath = await brewExecutablePath() else { return .missing }
        let brewEnvironment = readOnlyBrewEnvironment()

        async let formulae = runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: ["list", "--versions"],
            environment: brewEnvironment,
            timeout: 14
        ))
        async let casks = runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: ["list", "--cask", "--versions"],
            environment: brewEnvironment,
            timeout: 14
        ))
        async let outdated = runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: ["outdated", "--verbose"],
            environment: brewEnvironment,
            timeout: 18
        ))
        async let services = runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: ["services", "list", "--json"],
            environment: brewEnvironment,
            timeout: 12
        ))
        async let doctor = runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: ["doctor"],
            environment: brewEnvironment,
            timeout: 20
        ))

        let formulaeResult = await formulae
        let casksResult = await casks
        let outdatedResult = await outdated
        let servicesResult = await services
        let doctorResult = await doctor
        var errors: [String] = []

        var packages: [OpsBrewPackage] = []
        if formulaeResult.isSuccess {
            packages += OpsParsers.parseBrewListVersions(formulaeResult.stdout, kind: .formula)
        } else {
            errors.append("brew list --versions: \(formulaeResult.errorText)")
        }
        if casksResult.isSuccess {
            packages += OpsParsers.parseBrewListVersions(casksResult.stdout, kind: .cask)
        } else {
            errors.append("brew list --cask --versions: \(casksResult.errorText)")
        }
        let outdatedVersions: [String: String]
        if outdatedResult.isSuccess {
            outdatedVersions = OpsParsers.parseBrewOutdated(outdatedResult.stdout)
        } else {
            errors.append("brew outdated --verbose: \(outdatedResult.errorText)")
            outdatedVersions = [:]
        }
        packages = packages.map { package in
            var next = package
            next.latestVersion = outdatedVersions[package.name]
            return next
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let serviceItems = servicesResult.isSuccess
            ? OpsParsers.parseBrewServices(servicesResult.stdout.isEmpty ? servicesResult.stderr : servicesResult.stdout)
            : []
        if !servicesResult.isSuccess {
            errors.append("brew services list --json: \(servicesResult.errorText)")
        }
        let doctorOutput: String
        if doctorResult.isSuccess {
            doctorOutput = doctorResult.outputText.isEmpty ? "brew doctor produced no output." : doctorResult.outputText
        } else {
            errors.append("brew doctor: \(doctorResult.errorText)")
            doctorOutput = "Unable to run brew doctor: \(doctorResult.errorText)"
        }

        return OpsBrewSnapshot(
            brewPath: brewPath,
            packages: packages,
            services: serviceItems,
            doctorOutput: doctorOutput,
            lastCommandOutput: nil,
            errors: errors
        )
    }

    func loadEnvironment() async -> [OpsEnvironmentTool] {
        await withTaskGroup(of: OpsEnvironmentTool.self) { group in
            for definition in Self.environmentToolDefinitions {
                group.addTask {
                    await environmentTool(definition)
                }
            }

            var tools: [OpsEnvironmentTool] = []
            for await tool in group {
                tools.append(tool)
            }
            return tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func loadCleanupItems() async -> [OpsCleanupItem] {
        let brewPath = await brewExecutablePath()
        let dockerPath = trustedExecutablePath(named: "docker")
        let targets = cleanupTargets(brewPath: brewPath, dockerPath: dockerPath)
        return await Task.detached(priority: .utility) {
            targets.map { target in
                let exists: Bool
                let size: Int64?
                if let path = target.path {
                    exists = FileManager.default.fileExists(atPath: path)
                    size = exists ? Self.directorySize(at: URL(fileURLWithPath: path)) : nil
                } else {
                    exists = target.kind == .dockerSystem && dockerPath != nil
                    size = nil
                }
                return OpsCleanupItem(
                    kind: target.kind,
                    path: target.path,
                    sizeBytes: size,
                    isAvailable: exists,
                    detail: exists ? target.availableDetail : target.missingDetail
                )
            }
        }.value
    }

    func loadDiagnostics() async -> OpsDiagnosticsSnapshot {
        async let proxy = runner.run(OpsCommandInvocation(
            executablePath: "/usr/sbin/scutil",
            arguments: ["--proxy"],
            environment: environment,
            timeout: 5
        ))
        async let dns = runner.run(OpsCommandInvocation(
            executablePath: "/usr/sbin/scutil",
            arguments: ["--dns"],
            environment: environment,
            timeout: 5
        ))
        async let hosts = readHostsEntries()

        let proxyResult = await proxy
        let dnsResult = await dns
        var errors: [String] = []
        if !proxyResult.isSuccess {
            errors.append("scutil --proxy: \(proxyResult.errorText)")
        }
        if !dnsResult.isSuccess {
            errors.append("scutil --dns: \(dnsResult.errorText)")
        }

        return OpsDiagnosticsSnapshot(
            proxySummary: proxyResult.isSuccess ? OpsParsers.proxySummary(from: proxyResult.stdout) : "Unable to read system proxy settings.",
            dnsSummary: dnsResult.isSuccess ? OpsParsers.dnsSummary(from: dnsResult.stdout) : "Unable to read system DNS settings.",
            hostsEntries: await hosts,
            errors: errors
        )
    }

    func runURLDiagnostics(_ rawURL: String) async -> OpsURLDiagnosticResult {
        guard let url = normalizedURL(from: rawURL),
              let host = url.host(percentEncoded: false) else {
            return OpsURLDiagnosticResult(url: rawURL, headerText: "", tlsExpiration: nil, errorMessage: "Enter a valid URL.")
        }
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return OpsURLDiagnosticResult(url: rawURL, headerText: "", tlsExpiration: nil, errorMessage: "Only HTTP and HTTPS URLs are supported.")
        }

        let urlText = url.absoluteString
        async let headers = runner.run(OpsCommandInvocation(
            executablePath: "/usr/bin/curl",
            arguments: ["-I", "-L", "--proto", "=http,https", "--proto-redir", "=http,https", "--max-time", "8", "--silent", "--show-error", urlText],
            environment: environment,
            timeout: 10
        ))
        async let tls = tlsExpiration(host: host, port: url.port ?? 443, enabled: scheme == "https")

        let headerResult = await headers
        let expiration = await tls
        let error = headerResult.isSuccess ? nil : headerResult.errorText
        return OpsURLDiagnosticResult(
            url: urlText,
            headerText: headerResult.outputText,
            tlsExpiration: expiration,
            errorMessage: error?.isEmpty == true ? nil : error
        )
    }

    func terminate(target: OpsProcessIdentity, signal: Int32) async throws -> OpsTerminationOutcome {
        guard signal == SIGTERM || signal == SIGKILL else {
            throw OpsServiceError.invalidSignal
        }
        guard let current = try await processItem(pid: target.pid) else {
            throw OpsServiceError.processNotFound(target.pid)
        }
        if let reason = current.protection.reason {
            throw OpsServiceError.protectedProcess(reason)
        }
        guard current.identity.matches(target) else {
            throw OpsServiceError.processIdentityChanged
        }

        let code = Darwin.kill(target.pid, signal)
        guard code == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }

        try? await Task.sleep(nanoseconds: signal == SIGTERM ? 700_000_000 : 250_000_000)
        let stillRunning = Darwin.kill(target.pid, 0) == 0
        return OpsTerminationOutcome(pid: target.pid, signal: signal, isStillRunning: stillRunning)
    }

    func runBrew(action: OpsBrewAction) async throws -> OpsCommandResult {
        guard let brewPath = await brewExecutablePath() else {
            throw OpsServiceError.brewMissing
        }
        guard Self.brewActionIsAllowed(action) else {
            throw OpsServiceError.invalidBrewArguments
        }
        let arguments = action.arguments
        let result = await runner.run(OpsCommandInvocation(
            executablePath: brewPath,
            arguments: arguments,
            environment: environment,
            timeout: 120
        ))
        if !result.isSuccess {
            throw OpsCommandError.failed(executable: brewPath, arguments: arguments, result: result)
        }
        return result
    }

    func cleanup(kinds: Set<OpsCleanupKind>) async throws -> OpsCleanupResult {
        let brewPath = await brewExecutablePath()
        let dockerPath = trustedExecutablePath(named: "docker")
        let targets = Dictionary(uniqueKeysWithValues: cleanupTargets(brewPath: brewPath, dockerPath: dockerPath).map { ($0.kind, $0) })
        var removed = Set<OpsCleanupKind>()
        var skipped: [OpsCleanupKind: String] = [:]
        var commandOutput: String?

        for kind in kinds {
            guard let target = targets[kind] else {
                skipped[kind] = "No safe cleanup target is configured."
                continue
            }

            if kind == .dockerSystem {
                guard let dockerPath else {
                    skipped[kind] = "Docker was not found."
                    continue
                }
                let result = await runner.run(OpsCommandInvocation(
                    executablePath: dockerPath,
                    arguments: ["system", "prune", "--force"],
                    environment: environment,
                    timeout: 120
                ))
                if result.isSuccess {
                    removed.insert(kind)
                    commandOutput = result.outputText
                } else {
                    skipped[kind] = result.errorText
                }
                continue
            }

            guard let path = target.path else {
                skipped[kind] = "No safe cleanup path is configured."
                continue
            }

            do {
                let url = URL(fileURLWithPath: path)
                guard isSafeCleanupTarget(url, expectedPath: path) else {
                    skipped[kind] = "Cleanup target is not the expected allowlisted directory."
                    continue
                }
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(at: url)
                    removed.insert(kind)
                } else {
                    skipped[kind] = "Path no longer exists."
                }
            } catch {
                skipped[kind] = error.localizedDescription
            }
        }

        return OpsCleanupResult(removedKinds: removed, skippedKinds: skipped, commandOutput: commandOutput)
    }

    private func runRequired(executable: String, arguments: [String], timeout: TimeInterval) async throws -> OpsCommandResult {
        let result = await runner.run(OpsCommandInvocation(
            executablePath: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        ))
        guard result.isSuccess else {
            throw OpsCommandError.failed(executable: executable, arguments: arguments, result: result)
        }
        return result
    }

    private func processItem(pid: Int32) async throws -> OpsProcessItem? {
        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/bin/ps",
            arguments: ["-p", "\(pid)", "-ww", "-o", "pid=,ppid=,user=,pcpu=,pmem=,etime=,lstart=,command="],
            environment: environment,
            timeout: 3
        ))
        guard result.isSuccess else { return nil }
        return OpsParsers.parseProcessList(
            result.stdout,
            currentPID: Int32(ProcessInfo.processInfo.processIdentifier),
            currentUser: NSUserName()
        ).first { $0.pid == pid }
    }

    private func readOnlyBrewEnvironment() -> [String: String] {
        var next = environment
        next["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        next["HOMEBREW_NO_ANALYTICS"] = "1"
        return next
    }

    private func brewExecutablePath() async -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where isExecutable(path) {
            return path
        }
        return nil
    }

    private func executablePath(named command: String) async -> ResolvedExecutable? {
        for directory in searchPaths() {
            let candidate = directory.appendingPathComponent(command).path
            if isExecutable(candidate) {
                return ResolvedExecutable(path: candidate, isTrusted: isTrustedExecutablePath(candidate))
            }
        }
        return nil
    }

    private func trustedExecutablePath(named command: String) -> String? {
        for directory in Self.trustedExecutableDirectories {
            let candidate = directory.appendingPathComponent(command).path
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    private func searchPaths() -> [URL] {
        let pathValue = environment["PATH"] ?? ""
        let pathURLs = pathValue
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        return Self.trustedExecutableDirectories + pathURLs
    }

    private static let trustedExecutableDirectories: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        URL(fileURLWithPath: "/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/sbin", isDirectory: true),
        URL(fileURLWithPath: "/sbin", isDirectory: true),
    ]

    private func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private func isTrustedExecutablePath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return Self.trustedExecutableDirectories.contains { directory in
            standardized.hasPrefix(directory.standardizedFileURL.path + "/")
        }
    }

    private struct ResolvedExecutable: Sendable {
        var path: String
        var isTrusted: Bool
    }

    private func isSafeCleanupTarget(_ url: URL, expectedPath: String) -> Bool {
        let expected = URL(fileURLWithPath: expectedPath).standardizedFileURL.path
        guard url.standardizedFileURL.path == expected else { return false }
        guard expected.hasPrefix(homeDirectory.standardizedFileURL.path + "/") else { return false }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink != true
    }

    private struct EnvironmentToolDefinition: Sendable {
        var name: String
        var command: String
        var versionArguments: [String]
    }

    private static let environmentToolDefinitions: [EnvironmentToolDefinition] = [
        EnvironmentToolDefinition(name: "Git", command: "git", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Node", command: "node", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "npm", command: "npm", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "pnpm", command: "pnpm", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Yarn", command: "yarn", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Bun", command: "bun", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Python", command: "python3", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Ruby", command: "ruby", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Swift", command: "swift", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Xcodebuild", command: "xcodebuild", versionArguments: ["-version"]),
        EnvironmentToolDefinition(name: "GitHub CLI", command: "gh", versionArguments: ["--version"]),
        EnvironmentToolDefinition(name: "Docker", command: "docker", versionArguments: ["--version"]),
    ]

    private func environmentTool(_ definition: EnvironmentToolDefinition) async -> OpsEnvironmentTool {
        guard let resolved = await executablePath(named: definition.command) else {
            return OpsEnvironmentTool(
                name: definition.name,
                command: definition.command,
                resolvedPath: nil,
                version: nil,
                status: .missing,
                detail: "Not found in PATH.",
                isTrustedPath: false
            )
        }

        let result = await runner.run(OpsCommandInvocation(
            executablePath: resolved.path,
            arguments: definition.versionArguments,
            environment: environment,
            timeout: 6
        ))
        if result.isSuccess {
            return OpsEnvironmentTool(
                name: definition.name,
                command: definition.command,
                resolvedPath: resolved.path,
                version: OpsParsers.firstMeaningfulLine(result.outputText),
                status: .available,
                detail: resolved.isTrusted ? nil : "Resolved from a non-standard PATH directory.",
                isTrustedPath: resolved.isTrusted
            )
        }
        return OpsEnvironmentTool(
            name: definition.name,
            command: definition.command,
            resolvedPath: resolved.path,
            version: nil,
            status: .error(result.errorText),
            detail: result.errorText,
            isTrustedPath: resolved.isTrusted
        )
    }

    private struct CleanupTarget: Sendable {
        var kind: OpsCleanupKind
        var path: String?
        var availableDetail: String
        var missingDetail: String
    }

    private func cleanupTargets(brewPath: String?, dockerPath: String?) -> [CleanupTarget] {
        let home = homeDirectory
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        return [
            CleanupTarget(
                kind: .xcodeDerivedData,
                path: developer.appendingPathComponent("Xcode/DerivedData", isDirectory: true).path,
                availableDetail: "Removes Xcode build products and index data.",
                missingDetail: "No DerivedData directory was found."
            ),
            CleanupTarget(
                kind: .swiftPackageCache,
                path: caches.appendingPathComponent("org.swift.swiftpm", isDirectory: true).path,
                availableDetail: "Removes SwiftPM dependency cache data.",
                missingDetail: "No SwiftPM cache directory was found."
            ),
            CleanupTarget(
                kind: .npmCache,
                path: home.appendingPathComponent(".npm", isDirectory: true).path,
                availableDetail: "Removes npm cache contents.",
                missingDetail: "No npm cache directory was found."
            ),
            CleanupTarget(
                kind: .pnpmStore,
                path: home.appendingPathComponent("Library/pnpm/store", isDirectory: true).path,
                availableDetail: "Removes pnpm store contents.",
                missingDetail: "No pnpm store directory was found."
            ),
            CleanupTarget(
                kind: .yarnCache,
                path: caches.appendingPathComponent("Yarn", isDirectory: true).path,
                availableDetail: "Removes Yarn cache contents.",
                missingDetail: "No Yarn cache directory was found."
            ),
            CleanupTarget(
                kind: .homebrewCache,
                path: home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true).path,
                availableDetail: brewPath == nil ? "Homebrew cache directory exists, but brew was not found." : "Removes downloaded Homebrew cache artifacts.",
                missingDetail: "No Homebrew cache directory was found."
            ),
            CleanupTarget(
                kind: .dockerSystem,
                path: nil,
                availableDetail: "Runs docker system prune --force after confirmation.",
                missingDetail: dockerPath == nil ? "Docker was not found." : "Docker cleanup is unavailable."
            ),
        ]
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private func readHostsEntries() async -> [OpsHostEntry] {
        await Task.detached(priority: .utility) {
            guard let content = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return [] }
            return content
                .components(separatedBy: .newlines)
                .enumerated()
                .compactMap { index, line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
                    return OpsHostEntry(lineNumber: index + 1, rawLine: trimmed)
                }
        }.value
    }

    private func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: text)
    }

    private func tlsExpiration(host: String, port: Int, enabled: Bool) async -> Date? {
        guard enabled else { return nil }
        let openssl = trustedExecutablePath(named: "openssl") ?? "/usr/bin/openssl"
        guard isExecutable(openssl) else { return nil }

        let sClient = await runner.run(OpsCommandInvocation(
            executablePath: openssl,
            arguments: ["s_client", "-connect", "\(host):\(port)", "-servername", host, "-showcerts"],
            environment: environment,
            timeout: 8,
            standardInput: Data()
        ))
        guard let cert = OpsParsers.firstPEMCertificate(from: sClient.stdout + "\n" + sClient.stderr) else { return nil }

        let x509 = await runner.run(OpsCommandInvocation(
            executablePath: openssl,
            arguments: ["x509", "-noout", "-enddate"],
            environment: environment,
            timeout: 5,
            standardInput: Data(cert.utf8)
        ))
        return OpsParsers.parseOpenSSLNotAfter(x509.outputText)
    }

    static func brewActionIsAllowed(_ action: OpsBrewAction) -> Bool {
        switch action {
        case .install(let token), .uninstall(let token), .upgrade(let token):
            return brewTokenIsSafe(token)
        case .cleanup:
            return true
        case .service(_, let name):
            return brewTokenIsSafe(name)
        }
    }

    private static func brewTokenIsSafe(_ token: String) -> Bool {
        guard !token.isEmpty,
              !token.hasPrefix("-"),
              !token.contains("/"),
              !token.contains(".."),
              !token.contains("://"),
              !token.lowercased().hasSuffix(".rb") else {
            return false
        }
        let pattern = #"^[A-Za-z0-9+_.@-]+$"#
        return token.range(of: pattern, options: .regularExpression) != nil
    }
}

enum OpsServiceError: LocalizedError, Sendable {
    case brewMissing
    case invalidBrewArguments
    case invalidSignal
    case protectedProcess(String)
    case processIdentityChanged
    case processNotFound(Int32)

    var errorDescription: String? {
        switch self {
        case .brewMissing: "Homebrew was not found."
        case .invalidBrewArguments: "The Homebrew action contains unsupported arguments."
        case .invalidSignal: "Only SIGTERM and SIGKILL are supported."
        case .protectedProcess(let reason): "Process is protected: \(reason)"
        case .processIdentityChanged: "The process changed before the action could run. Refresh and try again."
        case .processNotFound(let pid): "Process \(pid) is no longer running."
        }
    }
}

enum OpsParsers {
    static func parseProcessList(
        _ output: String,
        currentPID: Int32 = Int32(ProcessInfo.processInfo.processIdentifier),
        currentUser: String = NSUserName(),
        executablePathResolver: @Sendable (Int32, String) -> String? = { pid, _ in processExecutablePath(pid: pid) }
    ) -> [OpsProcessItem] {
        output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(maxSplits: 11, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 7,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[3]),
                  let memory = Double(parts[4]) else {
                return nil
            }
            let startTime: String?
            let commandLine: String
            if parts.count >= 12 {
                startTime = parts[6...10].joined(separator: " ")
                commandLine = parts[11]
            } else {
                startTime = nil
                commandLine = parts.count > 7 ? parts[7] : parts[6]
            }
            let executable = executablePathResolver(pid, commandLine) ?? firstExecutableToken(from: commandLine)
            return OpsProcessItem(
                pid: pid,
                ppid: ppid,
                user: parts[2],
                cpuPercent: cpu,
                memoryPercent: memory,
                elapsed: parts[5],
                startTime: startTime,
                executablePath: executable,
                commandLine: commandLine,
                protection: protection(pid: pid, user: parts[2], displayName: URL(fileURLWithPath: executable).lastPathComponent, currentPID: currentPID, currentUser: currentUser)
            )
        }
    }

    static func parseLsofFieldOutput(_ output: String, processLookup: [Int32: OpsProcessItem]) -> [OpsPortItem] {
        struct CurrentProcess {
            var pid: Int32 = 0
            var command = ""
            var user = ""
            var proto = "TCP"
        }

        var current = CurrentProcess()
        var ports: [OpsPortItem] = []

        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            guard let key = line.first else { continue }
            let value = String(line.dropFirst())
            switch key {
            case "p":
                current = CurrentProcess(pid: Int32(value) ?? 0)
            case "c":
                current.command = value
            case "L":
                current.user = value
            case "P":
                current.proto = value.isEmpty ? "TCP" : value
            case "n":
                guard let endpoint = parseEndpoint(value), current.pid > 0 else { continue }
                let process = processLookup[current.pid]
                let user = current.user.isEmpty ? (process?.user ?? "") : current.user
                let name = current.command.isEmpty ? (process?.displayName ?? "Process \(current.pid)") : current.command
                let id = "\(current.pid)-\(endpoint.address)-\(endpoint.port)-\(current.proto)"
                ports.append(
                    OpsPortItem(
                        id: id,
                        pid: current.pid,
                        processIdentity: process?.identity ?? OpsProcessIdentity(
                            pid: current.pid,
                            ppid: 0,
                            user: user,
                            executablePath: process?.executablePath ?? name,
                            commandFingerprint: OpsProcessIdentity.fingerprint(process?.commandLine ?? name),
                            startTime: process?.startTime
                        ),
                        processName: name,
                        user: user,
                        protocolName: current.proto,
                        localAddress: endpoint.address,
                        port: endpoint.port,
                        commandLine: process?.commandLine ?? name,
                        executablePath: process?.executablePath,
                        protection: process?.protection ?? protection(pid: current.pid, user: user, displayName: name, currentPID: Int32(ProcessInfo.processInfo.processIdentifier), currentUser: NSUserName())
                    )
                )
            default:
                continue
            }
        }

        return ports.sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
        }
    }

    static func parseBrewListVersions(_ output: String, kind: OpsBrewPackageKind) -> [OpsBrewPackage] {
        output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return OpsBrewPackage(
                name: name,
                installedVersion: parts.count > 1 ? parts[1] : "installed",
                latestVersion: nil,
                kind: kind
            )
        }
    }

    static func parseBrewOutdated(_ output: String) -> [String: String] {
        if let json = parseBrewOutdatedJSON(output), !json.isEmpty { return json }
        var result: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "<")
            guard parts.count == 2 else { continue }
            let leftTokens = parts[0].split(separator: " ")
            guard let name = leftTokens.first else { continue }
            let latest = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .first
                .map(String.init) ?? ""
            if !latest.isEmpty { result[String(name)] = latest }
        }
        return result
    }

    static func parseBrewServices(_ output: String) -> [OpsBrewServiceItem] {
        if let data = output.data(using: .utf8) {
            if let array = try? JSONDecoder().decode([RawBrewService].self, from: data) {
                return array.map(\.item).sorted { $0.name < $1.name }
            }
            if let wrapper = try? JSONDecoder().decode(RawBrewServicesWrapper.self, from: data) {
                return wrapper.services.map(\.item).sorted { $0.name < $1.name }
            }
        }

        return output.components(separatedBy: .newlines).dropFirst().compactMap { line in
            let parts = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { return nil }
            return OpsBrewServiceItem(
                name: parts[0],
                status: parts[1],
                user: parts.count > 2 ? parts[2] : "",
                file: parts.count > 3 ? parts[3] : nil
            )
        }
    }

    static func firstMeaningfulLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func proxySummary(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let enabled = lines.filter { $0.contains("Enable") && $0.contains(": 1") }
        guard !enabled.isEmpty else { return "No system web proxy is enabled." }
        return enabled.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }

    static func dnsSummary(from output: String) -> String {
        let nameservers = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("nameserver[") }
            .prefix(6)
        return nameservers.isEmpty ? "No DNS nameservers reported by scutil." : nameservers.joined(separator: "\n")
    }

    static func firstPEMCertificate(from output: String) -> String? {
        guard let start = output.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = output.range(of: "-----END CERTIFICATE-----", range: start.lowerBound..<output.endIndex) else {
            return nil
        }
        return String(output[start.lowerBound..<end.upperBound])
    }

    static func parseOpenSSLNotAfter(_ output: String) -> Date? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.replacingOccurrences(of: "notAfter=", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        return formatter.date(from: raw)
    }

    private static func parseEndpoint(_ raw: String) -> (address: String, port: Int)? {
        var text = raw.replacingOccurrences(of: " (LISTEN)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("TCP ") {
            text.removeFirst(4)
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let portText = text[text.index(after: colon)...].filter(\.isNumber)
        guard let port = Int(String(portText)) else { return nil }
        var address = String(text[..<colon])
        address = address.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return (address, port)
    }

    private static func processExecutablePath(pid: Int32) -> String? {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let length = proc_pidpath(pid, buffer, UInt32(capacity))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func firstExecutableToken(from commandLine: String) -> String {
        commandLine.split(separator: " ").first.map(String.init) ?? commandLine
    }

    private static func protection(
        pid: Int32,
        user: String,
        displayName: String,
        currentPID: Int32,
        currentUser: String
    ) -> OpsProtection {
        if pid == currentPID { return .protected(reason: "This is Claude Stats.") }
        if pid <= 1 { return .protected(reason: "System launch process.") }
        if user == "root" { return .protected(reason: "Root-owned process.") }
        if !user.isEmpty, user != currentUser { return .protected(reason: "Owned by \(user).") }
        let critical = Set([
            "launchd", "kernel_task", "WindowServer", "loginwindow", "Finder",
            "SystemUIServer", "Dock", "cfprefsd", "distnoted", "tccd",
        ])
        if critical.contains(displayName) { return .protected(reason: "macOS system process.") }
        return .allowed
    }
}

private extension OpsProcessIdentity {
    func matches(_ other: OpsProcessIdentity) -> Bool {
        pid == other.pid
            && ppid == other.ppid
            && user == other.user
            && executablePath == other.executablePath
            && commandFingerprint == other.commandFingerprint
            && (startTime == nil || other.startTime == nil || startTime == other.startTime)
    }
}

private struct RawBrewService: Decodable {
    var name: String
    var status: String?
    var user: String?
    var file: String?

    var item: OpsBrewServiceItem {
        OpsBrewServiceItem(name: name, status: status ?? "unknown", user: user ?? "", file: file)
    }
}

private struct RawBrewServicesWrapper: Decodable {
    var services: [RawBrewService]
}

private struct RawBrewOutdatedResponse: Decodable {
    var formulae: [RawBrewOutdatedPackage]?
    var casks: [RawBrewOutdatedPackage]?
}

private struct RawBrewOutdatedPackage: Decodable {
    var name: String?
    var token: String?
    var current_version: String?
    var current_versions: [String]?

    var displayName: String? { name ?? token }
    var latest: String? { current_version ?? current_versions?.first }
}

private func parseBrewOutdatedJSON(_ output: String) -> [String: String]? {
    guard let data = output.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(RawBrewOutdatedResponse.self, from: data) else {
        return nil
    }
    let packages = (decoded.formulae ?? []) + (decoded.casks ?? [])
    return Dictionary(uniqueKeysWithValues: packages.compactMap { package in
        guard let name = package.displayName, let latest = package.latest else { return nil }
        return (name, latest)
    })
}
