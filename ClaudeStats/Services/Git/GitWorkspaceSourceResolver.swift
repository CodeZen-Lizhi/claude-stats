import Foundation

enum GitWorkspaceSourceID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case codex
    case cursor
    case windsurf
    case trae
    case traeCN
    case qoder
    case jetbrains

    var id: String { rawValue }
}

enum GitWorkspaceSourceKind: Sendable, Hashable {
    case sessionProvider(ProviderKind)
    case vscodeWorkspaceStorage(appSupportDirectoryName: String)
    case jetbrainsRecentProjects
}

struct GitWorkspaceSourceDescriptor: Sendable, Identifiable, Hashable {
    let id: GitWorkspaceSourceID
    let displayName: String
    let detail: String
    let assetName: String
    let kind: GitWorkspaceSourceKind

    var isSessionBacked: Bool {
        if case .sessionProvider = kind { return true }
        return false
    }
}

enum GitWorkspaceSourceCatalog {
    static let defaultEnabled: Set<GitWorkspaceSourceID> = [.codex]

    static let sessionSources: [GitWorkspaceSourceDescriptor] = [
        GitWorkspaceSourceDescriptor(
            id: .codex,
            displayName: "OpenAI Codex",
            detail: L10n.string("git.sources.codex.detail", defaultValue: "Repos from Codex session working directories."),
            assetName: "codex-logo",
            kind: .sessionProvider(.codex)
        ),
    ]

    static let editorSources: [GitWorkspaceSourceDescriptor] = [
        GitWorkspaceSourceDescriptor(
            id: .cursor,
            displayName: "Cursor",
            detail: L10n.string("git.sources.cursor.detail", defaultValue: "Matches Cursor workspace history against Codex repos."),
            assetName: "cursor-logo",
            kind: .vscodeWorkspaceStorage(appSupportDirectoryName: "Cursor")
        ),
        GitWorkspaceSourceDescriptor(
            id: .windsurf,
            displayName: "Windsurf",
            detail: L10n.string("git.sources.windsurf.detail", defaultValue: "Matches Windsurf workspace history against Codex repos."),
            assetName: "windsurf-logo",
            kind: .vscodeWorkspaceStorage(appSupportDirectoryName: "Windsurf")
        ),
        GitWorkspaceSourceDescriptor(
            id: .trae,
            displayName: "Trae",
            detail: L10n.string("git.sources.trae.detail", defaultValue: "Matches Trae workspace history against Codex repos."),
            assetName: "trae-logo",
            kind: .vscodeWorkspaceStorage(appSupportDirectoryName: "Trae")
        ),
        GitWorkspaceSourceDescriptor(
            id: .traeCN,
            displayName: "Trae CN",
            detail: L10n.string("git.sources.trae_cn.detail", defaultValue: "Matches Trae CN workspace history against Codex repos."),
            assetName: "trae-logo",
            kind: .vscodeWorkspaceStorage(appSupportDirectoryName: "Trae CN")
        ),
        GitWorkspaceSourceDescriptor(
            id: .qoder,
            displayName: "Qoder",
            detail: L10n.string("git.sources.qoder.detail", defaultValue: "Matches Qoder workspace history against Codex repos."),
            assetName: "qoder-logo",
            kind: .vscodeWorkspaceStorage(appSupportDirectoryName: "Qoder")
        ),
        GitWorkspaceSourceDescriptor(
            id: .jetbrains,
            displayName: "JetBrains",
            detail: L10n.string("git.sources.jetbrains.detail", defaultValue: "Matches JetBrains recent projects against Codex repos."),
            assetName: "",
            kind: .jetbrainsRecentProjects
        ),
    ]

    static var all: [GitWorkspaceSourceDescriptor] {
        sessionSources + editorSources
    }

    static func descriptor(for id: GitWorkspaceSourceID) -> GitWorkspaceSourceDescriptor? {
        all.first { $0.id == id }
    }

    static func normalized(_ ids: Set<GitWorkspaceSourceID>) -> Set<GitWorkspaceSourceID> {
        ids.union(defaultEnabled)
    }

    static func decodeStoredSourceIDs(_ raw: String?) -> Set<GitWorkspaceSourceID> {
        let values = (raw ?? "")
            .split(separator: ",")
            .map { String($0) }
        guard !values.isEmpty else { return defaultEnabled }

        let decoded = values.compactMap(GitWorkspaceSourceID.init(rawValue:))
        guard decoded.count == values.count, !decoded.isEmpty else { return defaultEnabled }
        return normalized(Set(decoded))
    }

    static func storageString(for ids: Set<GitWorkspaceSourceID>) -> String {
        GitWorkspaceSourceID.allCases
            .filter { ids.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func sessionProvider(for id: GitWorkspaceSourceID) -> ProviderKind? {
        guard case let .sessionProvider(provider) = descriptor(for: id)?.kind else { return nil }
        return provider
    }

    static func sourceID(for provider: ProviderKind) -> GitWorkspaceSourceID? {
        sessionSources.first {
            if case let .sessionProvider(sourceProvider) = $0.kind {
                return sourceProvider == provider
            }
            return false
        }?.id
    }
}

struct GitWorkspaceSourceResolver: Sendable {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL = Self.defaultApplicationSupportDirectory()) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    func cwds(
        sessions: [Session],
        enabledSources: Set<GitWorkspaceSourceID>
    ) -> [String] {
        let normalizedSources = GitWorkspaceSourceCatalog.normalized(enabledSources)
        var paths = Set<String>()

        for descriptor in GitWorkspaceSourceCatalog.sessionSources where normalizedSources.contains(descriptor.id) {
            guard case let .sessionProvider(provider) = descriptor.kind else { continue }
            for session in sessions where session.provider == provider {
                if let cwd = session.cwd {
                    insert(cwd, into: &paths)
                }
            }
        }

        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func enrichmentCwds(enabledSources: Set<GitWorkspaceSourceID>) -> [String] {
        let normalizedSources = GitWorkspaceSourceCatalog.normalized(enabledSources)
        var paths = Set<String>()

        for descriptor in GitWorkspaceSourceCatalog.editorSources where normalizedSources.contains(descriptor.id) {
            switch descriptor.kind {
            case let .vscodeWorkspaceStorage(appSupportDirectoryName):
                for path in vscodeWorkspacePaths(appSupportDirectoryName: appSupportDirectoryName) {
                    insert(path, into: &paths)
                }
            case .jetbrainsRecentProjects:
                for path in jetbrainsRecentProjectPaths() {
                    insert(path, into: &paths)
                }
            case .sessionProvider:
                continue
            }
        }

        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func sessionBackedSources(
        from sessions: [Session],
        enabledSources: Set<GitWorkspaceSourceID>
    ) -> [Session] {
        let enabledProviders = Set(
            GitWorkspaceSourceCatalog.normalized(enabledSources)
                .compactMap(GitWorkspaceSourceCatalog.sessionProvider(for:))
        )
        return sessions.filter { enabledProviders.contains($0.provider) }
    }

    private static func defaultApplicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
    }

    private func vscodeWorkspacePaths(appSupportDirectoryName: String) -> [String] {
        let workspaceStorageURL = applicationSupportDirectory
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("workspaceStorage", isDirectory: true)

        guard let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: workspaceStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var paths = Set<String>()
        for directory in workspaceDirs {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let workspaceJSONURL = directory.appendingPathComponent("workspace.json")
            for path in Self.paths(fromWorkspaceJSONAt: workspaceJSONURL) {
                insert(path, into: &paths)
            }
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func jetbrainsRecentProjectPaths() -> [String] {
        let jetBrainsURL = applicationSupportDirectory
            .appendingPathComponent("JetBrains", isDirectory: true)

        guard let appDirs = try? FileManager.default.contentsOfDirectory(
            at: jetBrainsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var paths = Set<String>()
        for appDir in appDirs {
            guard (try? appDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let xmlURL = appDir
                .appendingPathComponent("options", isDirectory: true)
                .appendingPathComponent("recentProjects.xml")
            for path in Self.paths(fromJetBrainsRecentProjectsXMLAt: xmlURL) {
                insert(path, into: &paths)
            }
        }

        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func insert(_ path: String, into paths: inout Set<String>) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        paths.insert(standardized)
    }

    static func paths(fromWorkspaceJSONAt url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var workspacePaths = Set<String>()
        if let folder = object["folder"] as? String,
           let path = localFilePath(from: folder) {
            workspacePaths.insert(path)
        }

        if let workspace = object["workspace"] as? String,
           let workspaceURL = localFileURL(from: workspace) {
            for path in paths(fromCodeWorkspaceAt: workspaceURL) {
                workspacePaths.insert(path)
            }
        }

        return workspacePaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { existingReadableDirectory(atPath: $0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func paths(fromCodeWorkspaceAt url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folders = object["folders"] as? [[String: Any]] else {
            return []
        }

        let baseURL = url.deletingLastPathComponent()
        var paths = Set<String>()
        for folder in folders {
            if let uri = folder["uri"] as? String,
               let path = localFilePath(from: uri) {
                paths.insert(path)
                continue
            }
            if let rawPath = folder["path"] as? String,
               let path = workspaceFolderPath(rawPath, relativeTo: baseURL) {
                paths.insert(path)
            }
        }

        return paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { existingReadableDirectory(atPath: $0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func paths(
        fromJetBrainsRecentProjectsXMLAt url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        let attributePattern = #"(?:key|value)="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: attributePattern) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var paths = Set<String>()

        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match,
                  let valueRange = Range(match.range(at: 1), in: xml) else { return }
            let raw = String(xml[valueRange])
            guard let path = jetBrainsProjectPath(from: raw, homeDirectory: homeDirectory) else { return }
            paths.insert(path)
        }

        return paths
            .filter { existingReadableDirectory(atPath: $0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func workspaceFolderPath(_ rawPath: String, relativeTo baseURL: URL) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let path = localFilePath(from: trimmed) {
            return path
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }
        return baseURL.appendingPathComponent(trimmed).standardizedFileURL.path
    }

    private static func localFilePath(from raw: String) -> String? {
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL.path
        }
        guard let url = localFileURL(from: raw) else { return nil }
        return url.standardizedFileURL.path
    }

    private static func localFileURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), url.isFileURL else { return nil }
        return url
    }

    private static func jetBrainsProjectPath(from raw: String, homeDirectory: URL) -> String? {
        let decoded = raw
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return nil }
        let expanded = decoded
            .replacingOccurrences(of: "$USER_HOME$", with: homeDirectory.path)
            .replacingOccurrences(of: "~", with: homeDirectory.path, options: [.anchored])
        if let path = localFilePath(from: expanded) {
            return path
        }
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func existingReadableDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }
}
