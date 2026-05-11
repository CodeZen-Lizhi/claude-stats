import Foundation

/// Reads Claude Code sessions from `~/.claude/projects/`.
struct ClaudeProvider: Provider {
    let paths: ClaudePaths
    let pricing: ModelPricing

    var kind: ProviderKind { .claude }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: paths.projectsDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    func discoverSessions() async -> [Session] {
        await SessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        await TranscriptParser(pricing: pricing)
            .parse(transcriptAt: URL(fileURLWithPath: session.filePath), fallbackTitle: session.projectDisplayName)
    }
}
