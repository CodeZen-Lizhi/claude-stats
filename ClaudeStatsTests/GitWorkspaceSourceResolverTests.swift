import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git workspace source resolver")
struct GitWorkspaceSourceResolverTests {
    @Test("Session sources include enabled providers only")
    func sessionSourcesRespectEnabledSources() {
        let resolver = GitWorkspaceSourceResolver(applicationSupportDirectory: URL(fileURLWithPath: "/tmp/unused"))
        let sessions = [
            session("claude", provider: .claude, cwd: "/work/claude"),
            session("codex", provider: .codex, cwd: "/work/codex"),
            session("gemini", provider: .gemini, cwd: "/work/gemini"),
            session("empty", provider: .claude, cwd: ""),
            session("nil", provider: .codex, cwd: nil),
        ]

        #expect(resolver.cwds(sessions: sessions, enabledSources: [.claude]) == ["/work/claude"])
        #expect(resolver.cwds(sessions: sessions, enabledSources: [.codex]) == ["/work/codex"])
        #expect(resolver.cwds(sessions: sessions, enabledSources: [.claude, .codex]) == ["/work/claude", "/work/codex"])
    }

    @Test("Cursor-style workspace folder JSON resolves local folder URI")
    func cursorWorkspaceFolderURI() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let project = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try writeWorkspaceJSON(
            #"{"folder":"\#(project.absoluteString)"}"#,
            appSupport: appSupport,
            appName: "Cursor",
            workspaceID: "abc"
        )

        let resolver = GitWorkspaceSourceResolver(applicationSupportDirectory: appSupport)
        #expect(resolver.cwds(sessions: [], enabledSources: [.cursor]) == [standardized(project)])
    }

    @Test("Code workspace resolves relative path, absolute path and file URI")
    func codeWorkspaceMultiRoot() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let workspaceDir = root.appendingPathComponent("Workspace", isDirectory: true)
        let relative = workspaceDir.appendingPathComponent("RelativeProject", isDirectory: true)
        let absolute = root.appendingPathComponent("AbsoluteProject", isDirectory: true)
        let fileURI = root.appendingPathComponent("FileURIProject", isDirectory: true)
        try FileManager.default.createDirectory(at: relative, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: absolute, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fileURI, withIntermediateDirectories: true)

        let workspaceFile = workspaceDir.appendingPathComponent("projects.code-workspace")
        let workspaceJSON = """
        {
          "folders": [
            { "path": "RelativeProject" },
            { "path": "\(absolute.path)" },
            { "uri": "\(fileURI.absoluteString)" },
            { "uri": "vscode-remote://ssh-remote/example/project" }
          ]
        }
        """
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        try workspaceJSON.write(to: workspaceFile, atomically: true, encoding: .utf8)
        try writeWorkspaceJSON(
            #"{"workspace":"\#(workspaceFile.absoluteString)"}"#,
            appSupport: appSupport,
            appName: "Cursor",
            workspaceID: "workspace"
        )

        let resolver = GitWorkspaceSourceResolver(applicationSupportDirectory: appSupport)
        #expect(Set(resolver.cwds(sessions: [], enabledSources: [.cursor])) == Set([
            standardized(relative),
            standardized(absolute),
            standardized(fileURI),
        ]))
    }

    @Test("Missing app support, remote URI and invalid JSON resolve to empty")
    func invalidExternalWorkspacesResolveEmpty() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let resolver = GitWorkspaceSourceResolver(applicationSupportDirectory: appSupport)

        #expect(resolver.cwds(sessions: [], enabledSources: [.cursor]).isEmpty)

        try writeWorkspaceJSON(
            #"{"folder":"vscode-remote://ssh-remote/example/project"}"#,
            appSupport: appSupport,
            appName: "Cursor",
            workspaceID: "remote"
        )
        try writeWorkspaceJSON(
            #"{broken json"#,
            appSupport: appSupport,
            appName: "Cursor",
            workspaceID: "invalid"
        )

        #expect(resolver.cwds(sessions: [], enabledSources: [.cursor]).isEmpty)
    }

    @Test("Multiple sources pointing into one repo are de-duplicated by git discovery", .enabled(if: GitAnalyzer().isAvailable))
    func duplicateSourcesDeduplicateToOneRepo() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let repo = root.appendingPathComponent("Repo", isDirectory: true)
        let subdir = repo.appendingPathComponent("Subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: repo)
        try writeWorkspaceJSON(
            #"{"folder":"\#(repo.absoluteString)"}"#,
            appSupport: appSupport,
            appName: "Cursor",
            workspaceID: "repo"
        )

        let resolver = GitWorkspaceSourceResolver(applicationSupportDirectory: appSupport)
        let cwds = resolver.cwds(
            sessions: [session("claude", provider: .claude, cwd: subdir.path)],
            enabledSources: [.claude, .cursor]
        )
        let repos = GitAnalyzer().repos(forCwds: cwds)

        #expect(repos.count == 1)
        #expect(repos.first.map { resolvedPath($0.rootPath) } == resolvedPath(repo.path))
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-workspace-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeWorkspaceJSON(
        _ json: String,
        appSupport: URL,
        appName: String,
        workspaceID: String
    ) throws {
        let dir = appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("workspaceStorage", isDirectory: true)
            .appendingPathComponent(workspaceID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("workspace.json"), atomically: true, encoding: .utf8)
    }

    private func standardized(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func session(_ id: String, provider: ProviderKind, cwd: String?) -> Session {
        Session(
            id: "\(provider.rawValue)-\(id)",
            externalID: id,
            provider: provider,
            projectDirectoryName: cwd ?? "",
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: .now,
            fileSize: 1,
            stats: SessionStats(
                title: id,
                messageCount: 1,
                firstActivity: .now,
                lastActivity: .now,
                models: [],
                timeline: []
            )
        )
    }

    private func runGit(_ args: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: GitAnalyzer.gitPath)
        process.arguments = ["-C", dir.path] + args
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "GitWorkspaceSourceResolverTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}
