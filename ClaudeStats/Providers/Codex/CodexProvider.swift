import Foundation

/// Reads OpenAI Codex CLI sessions from `~/.codex/sessions/`.
struct CodexProvider: Provider {
    let paths: CodexPaths
    let pricing: ModelPricing

    var kind: ProviderKind { .codex }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.sessionsDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { paths.sessionsDirectory.path }

    func discoverSessions() async -> [Session] {
        await CodexSessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        await CodexTranscriptParser(pricing: pricing)
            .parse(transcriptAt: URL(fileURLWithPath: session.filePath),
                   fallbackTitle: session.projectDisplayName)
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        await CodexTranscriptParser(pricing: pricing)
            .messages(transcriptAt: URL(fileURLWithPath: session.filePath))
    }

    func cacheHitRate(for usage: TokenUsage) -> Double? {
        usage.cachedInputRate
    }

    func usageLimitReport(now: Date) async -> UsageLimitReport {
        CodexUsageLimitLoader(paths: paths).report(now: now)
    }

    func globalConfigurationLocations() -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "config.toml",
                url: paths.homeDirectory.appendingPathComponent("config.toml", isDirectory: false),
                fileKind: .toml
            ),
            ProviderConfigLocation(
                provider: kind,
                title: "AGENTS.md",
                url: paths.homeDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }

    func projectConfigurationLocations(for projectURL: URL) -> [ProviderConfigLocation] {
        [
            ProviderConfigLocation(
                provider: kind,
                title: "Project AGENTS.md",
                url: projectURL.appendingPathComponent("AGENTS.md", isDirectory: false),
                fileKind: .markdown
            ),
        ]
    }
}
