import Foundation

/// Recognises the Kimi CLI but doesn't parse its usage yet — the on-disk log
/// location and format still need to be confirmed on a machine that has it.
///
// TODO: implement once Kimi CLI's session-log path/format is known.
struct KimiProvider: Provider {
    var kind: ProviderKind { .kimi }

    private var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi", isDirectory: true)
    }

    var dataDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dataDirectory.path, isDirectory: &isDir) && isDir.boolValue
    }

    var dataDirectoryPath: String? { dataDirectory.path }

    func discoverSessions() async -> [Session] { [] }

    func parse(_ session: Session) async -> SessionStats? { nil }
}
