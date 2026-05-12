import Foundation

/// Recognises MiniMax (Agent / CLI) but doesn't parse its usage yet — the
/// on-disk log location and format still need to be confirmed.
///
// TODO: implement once MiniMax's session-log path/format is known.
struct MiniMaxProvider: Provider {
    var kind: ProviderKind { .minimax }

    private var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minimax", isDirectory: true)
    }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dataDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { dataDirectory.path }

    func discoverSessions() async -> [Session] { [] }

    func parse(_ session: Session) async -> SessionStats? { nil }
}
