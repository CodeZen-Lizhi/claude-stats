import Foundation

struct CodexVersionStatus: Equatable, Sendable {
    var localVersion: String?
    var latestVersion: String?
    var localMessage: String
    var latestMessage: String

    static let loading = CodexVersionStatus(
        localVersion: nil,
        latestVersion: nil,
        localMessage: L10n.string("codex.version.checking", defaultValue: "Checking local Codex version..."),
        latestMessage: L10n.string("codex.version.checking_latest", defaultValue: "Checking latest release...")
    )

    var needsUpdate: Bool {
        guard let localVersion, let latestVersion else { return false }
        return localVersion != latestVersion
    }

    var statusLabel: String {
        guard localVersion != nil, latestVersion != nil else {
            return L10n.string("codex.version.unavailable", defaultValue: "Unavailable")
        }
        return L10n.string("codex.version.current", defaultValue: "Current")
    }

    var updateCommand: String {
        "npm install -g @openai/codex@latest"
    }
}

struct CodexVersionChecker: Sendable {
    private let latestURL: URL

    init(latestURL: URL = URL(string: "https://registry.npmjs.org/@openai/codex/latest")!) {
        self.latestURL = latestURL
    }

    func check() async -> CodexVersionStatus {
        async let local = CodexLocalVersionResolver.localVersion()
        async let latest = latestVersion()
        let resolvedLocal = await local
        let resolvedLatest = await latest
        return CodexVersionStatus(
            localVersion: resolvedLocal.version,
            latestVersion: resolvedLatest.version,
            localMessage: resolvedLocal.message,
            latestMessage: resolvedLatest.message
        )
    }

    private func latestVersion() async -> (version: String?, message: String) {
        do {
            let (data, response) = try await URLSession.shared.data(from: latestURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (nil, L10n.string("codex.version.latest_registry_error", defaultValue: "npm registry returned an error."))
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let version = object?["version"] as? String
            return (version, version ?? L10n.string("codex.version.latest_missing_field", defaultValue: "No version field in npm latest metadata."))
        } catch {
            return (nil, L10n.string("codex.version.latest_network_error", defaultValue: "Unable to check the npm registry."))
        }
    }
}

struct CodexLocalVersionResolver {
    static func localVersion() async -> (version: String?, message: String) {
        await Task.detached(priority: .utility) {
            var lastOutput: String?
            for candidate in commandCandidates() {
                let result = run(candidate)
                guard result.exitCode == 0 else {
                    if !result.output.isEmpty {
                        lastOutput = result.output
                    }
                    continue
                }
                let version = extractVersion(from: result.output)
                return (version, version ?? result.output)
            }
            return (
                nil,
                lastOutput.flatMap(localizedFailureMessage(from:))
                    ?? L10n.string(
                        "codex.version.local_not_found",
                        defaultValue: "Codex CLI was not found in PATH or common install locations."
                    )
            )
        }.value
    }

    static func commandCandidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> [CodexCommandCandidate] {
        let path = enrichedPATH(environment: environment, homeDirectory: homeDirectory)
        var env = environment
        env["PATH"] = path
        return [
            CodexCommandCandidate(
                executablePath: "/usr/bin/env",
                arguments: ["codex", "--version"],
                environment: env
            ),
            CodexCommandCandidate(
                executablePath: "/bin/zsh",
                arguments: ["-lc", "codex --version"],
                environment: env
            ),
            CodexCommandCandidate(
                executablePath: "/bin/zsh",
                arguments: ["-ic", "codex --version"],
                environment: env
            )
        ]
    }

    static func enrichedPATH(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        let existing = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let common = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.npm-global/bin",
            "\(homeDirectory)/.volta/bin",
            "\(homeDirectory)/.bun/bin",
            "\(homeDirectory)/.yarn/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return unique(common + existing).joined(separator: ":")
    }

    static func extractVersion(from output: String) -> String? {
        output
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .map(String.init)
            .first { $0.contains(".") }
    }

    private static func run(_ candidate: CodexCommandCandidate) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: candidate.executablePath)
        process.arguments = candidate.arguments
        process.environment = candidate.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private static func localizedFailureMessage(from output: String) -> String {
        if output.localizedCaseInsensitiveContains("no such file or directory")
            || output.localizedCaseInsensitiveContains("command not found") {
            return L10n.string(
                "codex.version.local_not_found",
                defaultValue: "Codex CLI was not found in PATH or common install locations."
            )
        }
        return L10n.string(
            "codex.version.local_failed",
            defaultValue: "Unable to read the local Codex version."
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct CodexCommandCandidate: Equatable, Sendable {
    var executablePath: String
    var arguments: [String]
    var environment: [String: String]
}
