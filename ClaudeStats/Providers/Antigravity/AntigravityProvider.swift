import Foundation

/// Recognises Antigravity (the Gemini-powered VS Code fork) but doesn't parse
/// its usage yet.
///
/// Antigravity stores its agent state in `state.vscdb` (SQLite) under
/// `~/Library/Application Support/Antigravity/User/globalStorage/` plus
/// `~/.gemini/antigravity/`, but the keys that would carry per-conversation
/// model + token counts are empty on the machines inspected so far (the
/// trajectory data appears to live server-side). Until a usable on-disk
/// format turns up, `discoverSessions()` returns nothing.
///
// TODO: implement once the trajectory/usage storage format is confirmed.
struct AntigravityProvider: Provider {
    var kind: ProviderKind { .antigravity }

    private var globalStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage", isDirectory: true)
    }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: globalStorageDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { globalStorageDirectory.path }

    func discoverSessions() async -> [Session] { [] }

    func parse(_ session: Session) async -> SessionStats? { nil }
}
