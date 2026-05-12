import Foundation

/// Recognises the Gemini CLI / Antigravity but doesn't parse its usage yet.
///
/// Gemini-family tools keep state under `~/.gemini/` (the CLI's logs, the
/// Antigravity IDE fork's `state.vscdb`, etc.), but the per-conversation model
/// + token records aren't in a usable on-disk form on the machines inspected
/// so far (the trajectory data appears to live server-side). Until that's
/// confirmed, `discoverSessions()` returns nothing.
///
// TODO: implement once the Gemini CLI session-log path/format is confirmed.
struct GeminiProvider: Provider {
    var kind: ProviderKind { .gemini }

    private var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true)
    }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dataDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { dataDirectory.path }

    func discoverSessions() async -> [Session] { [] }

    func parse(_ session: Session) async -> SessionStats? { nil }
}
