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

        var rawSessions: [RawSession] = []
        let titleIndex = Self.readSessionTitleIndex(from: paths.sessionIndexFile)
        for url in Self.rolloutFiles(under: root) {
            let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            guard size >= Self.minimumFileSize else { continue }
            let modified = values?.contentModificationDate ?? .distantPast

            let meta = Self.readSessionMeta(from: url)
            let uuid = meta?.id ?? Self.uuidFromFilename(url.lastPathComponent) ?? url.deletingPathExtension().lastPathComponent
            let titleOverride = titleIndex[uuid]
            rawSessions.append(RawSession(
                id: "codex::\(uuid)",
                externalID: uuid,
                url: url,
                cwd: meta?.cwd,
                titleOverride: titleOverride,
                titleFallback: meta?.titleFallback,
                lastModified: modified,
                fileSize: size,
                agentInfo: meta?.agentInfo
            ))
        }

        return resolveProjects(for: rawSessions).sorted { $0.lastModified > $1.lastModified }
    }

    private func resolveProjects(for rawSessions: [RawSession]) -> [Session] {
        let explicitProjects = Self.explicitProjectDirectories(from: rawSessions)
        let projectByName = Dictionary(
            explicitProjects.map { (($0 as NSString).lastPathComponent, $0) },
            uniquingKeysWith: { first, second in first.count <= second.count ? first : second }
        )

        var resolutionByID: [String: ProjectResolution] = [:]
        for raw in rawSessions {
            resolutionByID[raw.id] = Self.initialResolution(for: raw, projectByName: projectByName)
        }

        for raw in rawSessions {
            guard let parentID = raw.agentInfo?.parentSessionID,
                  var resolution = resolutionByID[raw.id],
                  resolution.sourceKind == .agent,
                  let parentResolution = resolutionByID[parentID],
                  parentResolution.sourceKind != .agent else {
                continue
            }
            resolution = parentResolution.withSourceKind(.agent)
            resolutionByID[raw.id] = resolution
        }

        return rawSessions.map { raw in
            let resolution = resolutionByID[raw.id] ?? ProjectResolution.agentSessions
            return Session(
                id: raw.id,
                externalID: raw.externalID,
                provider: .codex,
                projectDirectoryName: resolution.groupKey,
                projectDisplayNameOverride: resolution.displayName,
                filePath: raw.url.path,
                cwd: raw.cwd,
                titleOverride: raw.titleOverride,
                titleFallback: raw.titleFallback ?? resolution.titleFallback,
                sourceKind: resolution.sourceKind,
                lastModified: raw.lastModified,
                fileSize: raw.fileSize,
                stats: nil,
                agentInfo: raw.agentInfo
            )
        }
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

    struct SessionMeta {
        let id: String?
        let cwd: String?
        let titleFallback: String?
        let agentInfo: SessionAgentInfo?
    }

    static func readSessionTitleIndex(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        struct Entry: Decodable {
            let id: String?
            let threadName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case threadName = "thread_name"
            }
        }

        let decoder = JSONDecoder()
        var titles: [String: String] = [:]
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(Entry.self, from: Data(lineBytes)),
                  let id = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  let title = entry.threadName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                continue
            }
            titles[id] = title
        }
        return titles
    }

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
            struct Payload: Decodable {
                let id: String?
                let cwd: String?
                let source: FlexibleSource?
                let threadSource: String?
                let agentNickname: String?
                let agentRole: String?
                let agentPath: String?
                let forkedFromID: String?

                enum CodingKeys: String, CodingKey {
                    case id, cwd, source
                    case threadSource = "thread_source"
                    case agentNickname = "agent_nickname"
                    case agentRole = "agent_role"
                    case agentPath = "agent_path"
                    case forkedFromID = "forked_from_id"
                }
            }

            struct FlexibleSource: Decodable {
                let subagent: Subagent?

                init(from decoder: Decoder) throws {
                    if let source = try? Source(from: decoder) {
                        self.subagent = source.subagent
                    } else {
                        let container = try decoder.singleValueContainer()
                        _ = try? container.decode(String.self)
                        self.subagent = nil
                    }
                }
            }

            struct Source: Decodable {
                let subagent: Subagent?
            }

            struct Subagent: Decodable {
                let threadSpawn: ThreadSpawn?
                enum CodingKeys: String, CodingKey { case threadSpawn = "thread_spawn" }
            }

            struct ThreadSpawn: Decodable {
                let parentThreadID: String?
                enum CodingKeys: String, CodingKey { case parentThreadID = "parent_thread_id" }
            }
        }
        guard let line = try? JSONDecoder().decode(Line.self, from: Data(firstLine)),
              line.type == "session_meta" else { return nil }
        let explicitParentID = line.payload?.source?.subagent?.threadSpawn?.parentThreadID
        let isAgentCwd = line.payload?.cwd.map(Self.isAgentDirectory) ?? false
        let forkedParentID = isAgentCwd ? line.payload?.forkedFromID : nil
        let parentID = (explicitParentID ?? forkedParentID).map(Self.sessionID)
        let agentInfo = SessionAgentInfo(
            threadSource: line.payload?.threadSource,
            parentSessionID: parentID,
            nickname: line.payload?.agentNickname,
            role: line.payload?.agentRole,
            path: line.payload?.agentPath
        )
        let hasAgentInfo = agentInfo.threadSource == "subagent"
            || agentInfo.parentSessionID != nil
            || agentInfo.nickname != nil
            || agentInfo.role != nil
            || agentInfo.path != nil
            || isAgentCwd
        return SessionMeta(
            id: line.payload?.id,
            cwd: line.payload?.cwd,
            titleFallback: Self.titleFallback(for: line.payload?.cwd, agentInfo: hasAgentInfo ? agentInfo : nil),
            agentInfo: hasAgentInfo ? agentInfo : nil
        )
    }

    /// Fallback id extraction from `rollout-<timestamp>-<uuid>.jsonl` — the
    /// uuid is the last five dash-separated groups of the filename stem.
    static func uuidFromFilename(_ name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        let parts = stem.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        return parts.suffix(5).joined(separator: "-")
    }

    private struct RawSession {
        let id: String
        let externalID: String
        let url: URL
        let cwd: String?
        let titleOverride: String?
        let titleFallback: String?
        let lastModified: Date
        let fileSize: Int64
        let agentInfo: SessionAgentInfo?
    }

    private struct ProjectResolution {
        let groupKey: String
        let displayName: String?
        let titleFallback: String?
        let sourceKind: SessionSourceKind

        static let agentSessions = ProjectResolution(
            groupKey: "codex::agent-sessions",
            displayName: "Agent Sessions",
            titleFallback: "Agent session",
            sourceKind: .agent
        )

        func withSourceKind(_ sourceKind: SessionSourceKind) -> ProjectResolution {
            ProjectResolution(
                groupKey: groupKey,
                displayName: displayName,
                titleFallback: titleFallback,
                sourceKind: sourceKind
            )
        }
    }

    private static func explicitProjectDirectories(from rawSessions: [RawSession]) -> Set<String> {
        Set(rawSessions.compactMap { raw in
            guard let cwd = raw.cwd,
                  !isSyntheticCodexDirectory(cwd),
                  !isAgentDirectory(cwd) else {
                return nil
            }
            return standardizedPath(cwd)
        })
    }

    private static func initialResolution(
        for raw: RawSession,
        projectByName: [String: String]
    ) -> ProjectResolution {
        guard let cwd = raw.cwd, !cwd.isEmpty else {
            return ProjectResolution(
                groupKey: "codex::unknown-project",
                displayName: "Unknown Project",
                titleFallback: nil,
                sourceKind: .project
            )
        }

        let path = standardizedPath(cwd)
        if isAgentDirectory(path) {
            return .agentSessions
        }
        if let worktreeName = worktreeProjectName(from: path) {
            let matched = projectByName[worktreeName]
            return ProjectResolution(
                groupKey: matched ?? "codex::worktree::\(worktreeName)",
                displayName: worktreeName,
                titleFallback: worktreeName,
                sourceKind: .worktree
            )
        }
        if let slug = adHocSlug(from: path) {
            return ProjectResolution(
                groupKey: "codex::ad-hoc-sessions",
                displayName: "Ad-hoc Codex Sessions",
                titleFallback: titleizeSlug(slug),
                sourceKind: .adHoc
            )
        }
        return ProjectResolution(
            groupKey: path,
            displayName: (path as NSString).lastPathComponent,
            titleFallback: nil,
            sourceKind: .project
        )
    }

    private static func titleFallback(for cwd: String?, agentInfo: SessionAgentInfo?) -> String? {
        if let agentTitle = agentInfo?.displayTitle, agentTitle != "Subagent" {
            return agentTitle
        }
        guard let cwd else { return nil }
        let path = standardizedPath(cwd)
        if let slug = adHocSlug(from: path) {
            return titleizeSlug(slug)
        }
        if let worktreeName = worktreeProjectName(from: path) {
            return worktreeName
        }
        return nil
    }

    private static func sessionID(_ rawID: String) -> String {
        rawID.hasPrefix("codex::") ? rawID : "codex::\(rawID)"
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isSyntheticCodexDirectory(_ path: String) -> Bool {
        worktreeProjectName(from: path) != nil || adHocSlug(from: path) != nil
    }

    private static func isAgentDirectory(_ path: String) -> Bool {
        standardizedPath(path).contains("/.cumora/agents/")
    }

    private static func worktreeProjectName(from path: String) -> String? {
        let parts = standardizedPath(path).split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: ".codex"),
              parts.indices.contains(index + 1),
              parts[index + 1] == "worktrees",
              let name = parts.last,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private static func adHocSlug(from path: String) -> String? {
        let parts = standardizedPath(path).split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "Documents"),
              parts.indices.contains(index + 3),
              parts[index + 1] == "Codex",
              parts[index + 2].range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return parts[index + 3]
    }

    private static func titleizeSlug(_ slug: String) -> String {
        let cleaned = slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? slug : cleaned
    }
}
