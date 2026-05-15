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
}
