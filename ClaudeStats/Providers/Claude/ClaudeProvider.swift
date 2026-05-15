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

    var dataDirectoryPath: String? { paths.projectsDirectory.path }

    func discoverSessions() async -> [Session] {
        await SessionScanner(paths: paths).scan()
    }

    func parse(_ session: Session) async -> SessionStats? {
        await TranscriptParser(pricing: pricing)
            .parse(transcriptAt: URL(fileURLWithPath: session.filePath), fallbackTitle: session.projectDisplayName)
    }

    /// Pretty label for Anthropic's canonical model ids:
    /// `claude-opus-4-7` → `Opus 4.7`, `claude-haiku-4-5` → `Haiku 4.5`,
    /// `claude-3.5-sonnet` → `Sonnet 3.5`. Unknown shapes fall back to a
    /// hyphen-cleaned, capitalised form so a previously-unseen id is still
    /// readable.
    func displayName(forModel id: String) -> String {
        Self.prettyName(for: id)
    }

    static func prettyName(for id: String) -> String {
        var stripped = id
        if stripped.hasPrefix("claude-") { stripped.removeFirst("claude-".count) }
        let parts = stripped.split(separator: "-", omittingEmptySubsequences: true).map(String.init)

        // `family-major-minor` (modern): opus-4-7, sonnet-4-6, haiku-4-5
        if parts.count == 3,
           let major = Int(parts[1]), let minor = Int(parts[2]) {
            return "\(parts[0].capitalized) \(major).\(minor)"
        }
        // `family-major` (no minor): opus-4
        if parts.count == 2, Int(parts[1]) != nil {
            return "\(parts[0].capitalized) \(parts[1])"
        }
        // `major.minor-family` (legacy): 3.5-sonnet, 3-opus
        if parts.count == 2,
           Double(parts[0]) != nil {
            return "\(parts[1].capitalized) \(parts[0])"
        }
        // Fallback: hyphen-cleaned, capitalised. Preserves any embedded dots.
        return parts.map { part in
            guard let head = part.first else { return "" }
            return String(head).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
}
