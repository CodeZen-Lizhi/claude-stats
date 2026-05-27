import Foundation

/// Where the OpenAI Codex CLI keeps its data on disk. Injectable so tests can
/// point it at a temp directory.
struct CodexPaths: Sendable, Hashable {
    /// `~/.codex` (or `$CODEX_HOME` when set).
    let homeDirectory: URL

    /// `<homeDirectory>/sessions` — rollout transcripts under `YYYY/MM/DD/`.
    var sessionsDirectory: URL { homeDirectory.appendingPathComponent("sessions", isDirectory: true) }

    /// `<homeDirectory>/session_index.jsonl` — Codex's user-facing thread names.
    var sessionIndexFile: URL { homeDirectory.appendingPathComponent("session_index.jsonl", isDirectory: false) }

    init(homeDirectory: URL) { self.homeDirectory = homeDirectory }

    static let `default`: CodexPaths = {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return CodexPaths(homeDirectory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CodexPaths(homeDirectory: home.appendingPathComponent(".codex", isDirectory: true))
    }()
}
