import Foundation

protocol OpsServicing: Sendable {
    func loadBrew() async -> OpsBrewSnapshot
    func loadEnvironment() async -> [OpsEnvironmentTool]
    func runBrew(action: OpsBrewAction) async throws -> OpsCommandResult
}

struct OpsService: OpsServicing {
    private let runner: any OpsCommandRunning
    private let environment: [String: String]

    init(
        runner: any OpsCommandRunning = DefaultOpsCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runner = runner
        self.environment = environment
    }

    func loadBrew() async -> OpsBrewSnapshot {
        guard let brewPath = await brewExecutablePath() else { return .missing }
        let brewEnvironment = readOnlyBrewEnvironment(brewPath: brewPath)

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
        let doctorPresentation = Self.brewDoctorPresentation(for: doctorResult)
        if let doctorError = doctorPresentation.error {
            errors.append(doctorError)
        }

        return OpsBrewSnapshot(
            brewPath: brewPath,
            packages: packages,
            services: serviceItems,
            doctorOutput: doctorPresentation.output,
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

    private func readOnlyBrewEnvironment(brewPath: String) -> [String: String] {
        Self.readOnlyBrewEnvironment(base: environment, brewPath: brewPath)
    }

    static func readOnlyBrewEnvironment(base environment: [String: String], brewPath: String) -> [String: String] {
        var next = environment
        next["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        next["HOMEBREW_NO_ANALYTICS"] = "1"
        next["PATH"] = brewAwarePath(existingPath: environment["PATH"], brewPath: brewPath)
        return next
    }

    static func brewDoctorPresentation(for result: OpsCommandResult) -> (output: String, error: String?) {
        let output = result.outputText
        if result.isSuccess {
            return (output.isEmpty ? "brew doctor produced no output." : output, nil)
        }

        if !output.isEmpty, result.launchError == nil, !result.timedOut {
            return (output, nil)
        }

        let error = result.errorText
        return ("Unable to run brew doctor: \(error)", "brew doctor: \(error)")
    }

    private static func brewAwarePath(existingPath: String?, brewPath: String) -> String {
        let brewBinDirectory = URL(fileURLWithPath: brewPath).deletingLastPathComponent()
        let brewPrefix = brewBinDirectory.deletingLastPathComponent()
        let preferredPaths = [
            brewPrefix.appendingPathComponent("bin", isDirectory: true).path,
            brewPrefix.appendingPathComponent("sbin", isDirectory: true).path,
        ]
        let fallbackPaths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPaths = existingPath?
            .split(separator: ":")
            .map(String.init) ?? []

        var seen = Set<String>()
        return (preferredPaths + existingPaths + fallbackPaths)
            .filter { path in
                guard !path.isEmpty, !seen.contains(path) else { return false }
                seen.insert(path)
                return true
            }
            .joined(separator: ":")
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

    static func brewActionIsAllowed(_ action: OpsBrewAction) -> Bool {
        switch action {
        case .install(let token), .uninstall(let token), .upgrade(let token):
            return brewTokenIsSafe(token)
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

    var errorDescription: String? {
        switch self {
        case .brewMissing: "Homebrew was not found."
        case .invalidBrewArguments: "The Homebrew action contains unsupported arguments."
        }
    }
}

enum OpsParsers {
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
