import Foundation

/// Walks `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` and turns each rollout
/// transcript into a ``Session`` with cheap metadata only (no full parse).
struct CodexSessionScanner: Sendable {
    let paths: CodexPaths

    /// Files smaller than this are almost certainly empty/aborted sessions.
    static let minimumFileSize: Int64 = 200

    private static let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]

    func scan() async -> [Session] {
        let fm = FileManager.default
        let root = paths.sessionsDirectory
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }

        var sessions: [Session] = []
        for url in Self.rolloutFiles(under: root) {
            let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            guard size >= Self.minimumFileSize else { continue }
            let modified = values?.contentModificationDate ?? .distantPast

            let meta = Self.readSessionMeta(from: url)
            let uuid = meta?.id ?? Self.uuidFromFilename(url.lastPathComponent) ?? url.deletingPathExtension().lastPathComponent
            sessions.append(Session(
                id: "codex::\(uuid)",
                externalID: uuid,
                provider: .codex,
                projectDirectoryName: meta?.cwd ?? "",
                filePath: url.path,
                cwd: meta?.cwd,
                lastModified: modified,
                fileSize: size
            ))
        }
        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    /// All `rollout-*.jsonl` files under `root` (recursively). Synchronous so
    /// the `DirectoryEnumerator` iteration isn't done from an async context.
    private static func rolloutFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: resourceKeys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            out.append(url)
        }
        return out
    }

    // MARK: First-line metadata

    struct SessionMeta { let id: String?; let cwd: String? }

    /// Read the first JSONL line (`type == "session_meta"`) to pull `id` and
    /// `cwd` without decoding the whole file.
    static func readSessionMeta(from url: URL) -> SessionMeta? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return nil }
        let firstLine = chunk.prefix { $0 != 0x0A /* \n */ }
        struct Line: Decodable {
            let type: String?
            let payload: Payload?
            struct Payload: Decodable { let id: String?; let cwd: String? }
        }
        guard let line = try? JSONDecoder().decode(Line.self, from: Data(firstLine)),
              line.type == "session_meta" else { return nil }
        return SessionMeta(id: line.payload?.id, cwd: line.payload?.cwd)
    }

    /// Fallback id extraction from `rollout-<timestamp>-<uuid>.jsonl` — the
    /// uuid is the last five dash-separated groups of the filename stem.
    static func uuidFromFilename(_ name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        let parts = stem.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        return parts.suffix(5).joined(separator: "-")
    }
}
