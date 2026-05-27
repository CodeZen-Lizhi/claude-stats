import Foundation

/// A single transcript discovered on disk. Cheap metadata is filled by the
/// scanner; ``stats`` is parsed lazily (and cached) by ``SessionStore``.
struct Session: Sendable, Identifiable, Hashable {
    /// Stable id: `"<encoded-project-dir>::<transcript-uuid>"`.
    let id: String
    /// The transcript file's own basename without extension (the session UUID).
    let externalID: String
    let provider: ProviderKind
    /// The encoded project directory name from the provider's session storage.
    let projectDirectoryName: String
    /// Human-friendly project name when the provider can resolve a synthetic
    /// working directory back to a stable project group.
    let projectDisplayNameOverride: String?
    /// Absolute path of the `.jsonl` transcript.
    let filePath: String
    /// Working directory the session ran in, if it could be read cheaply.
    let cwd: String?
    /// Provider-supplied title fallback used when the transcript has no title.
    let titleFallback: String?
    /// Coarse source bucket for UI hints; does not affect usage accounting.
    let sourceKind: SessionSourceKind
    let lastModified: Date
    let fileSize: Int64

    /// Filled in after parsing. `nil` until ``SessionStore`` parses it.
    var stats: SessionStats?
    /// Provider-owned agent metadata. Present for Codex subagent transcripts.
    var agentInfo: SessionAgentInfo? = nil
    /// Child agent sessions confidently attributed to this parent.
    var childSessions: [Session] = []

    init(
        id: String,
        externalID: String,
        provider: ProviderKind,
        projectDirectoryName: String,
        projectDisplayNameOverride: String? = nil,
        filePath: String,
        cwd: String?,
        titleFallback: String? = nil,
        sourceKind: SessionSourceKind = .project,
        lastModified: Date,
        fileSize: Int64,
        stats: SessionStats? = nil,
        agentInfo: SessionAgentInfo? = nil,
        childSessions: [Session] = []
    ) {
        self.id = id
        self.externalID = externalID
        self.provider = provider
        self.projectDirectoryName = projectDirectoryName
        self.projectDisplayNameOverride = projectDisplayNameOverride
        self.filePath = filePath
        self.cwd = cwd
        self.titleFallback = titleFallback
        self.sourceKind = sourceKind
        self.lastModified = lastModified
        self.fileSize = fileSize
        self.stats = stats
        self.agentInfo = agentInfo
        self.childSessions = childSessions
    }

    /// Display name for the project: the real `cwd`'s last path component,
    /// falling back to a de-mangled form of the encoded directory name.
    var projectDisplayName: String {
        if let projectDisplayNameOverride, !projectDisplayNameOverride.isEmpty {
            return projectDisplayNameOverride
        }
        if let cwd, !cwd.isEmpty {
            let name = (cwd as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        // Claude encodes `/Users/me/dev/foo` as `-Users-me-dev-foo`.
        let parts = projectDirectoryName.split(separator: "-")
        return parts.last.map(String.init) ?? projectDirectoryName
    }

    var sourceBadge: String? {
        sourceKind.badge
    }
}

enum SessionSourceKind: String, Sendable, Hashable, Codable {
    case project
    case worktree
    case agent
    case adHoc

    var badge: String? {
        switch self {
        case .project:
            nil
        case .worktree:
            "worktree"
        case .agent:
            "agent"
        case .adHoc:
            "ad-hoc"
        }
    }
}
