import Testing
import Foundation
@testable import ClaudeStats

@Suite("CodexSessionScanner")
struct CodexSessionScannerTests {

    @Test("Discovers rollout transcripts, skips tiny/non-rollout files, reads cwd + id")
    func scansSessionsTree() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)

        let fileName = "rollout-2026-01-10T09-00-00-\(CodexSampleTranscript.sessionID).jsonl"
        try TempDir.write(CodexSampleTranscript.text, to: dayDir.appendingPathComponent(fileName))
        // Below the size floor — ignored.
        try TempDir.write("{}", to: dayDir.appendingPathComponent("rollout-2026-01-10T09-01-00-tiny.jsonl"))
        // Not a rollout file — ignored.
        try TempDir.write(String(repeating: "x", count: 500), to: dayDir.appendingPathComponent("notes.jsonl"))

        let sessions = await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan()

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.provider == .codex)
        #expect(session.id == "codex::\(CodexSampleTranscript.sessionID)")
        #expect(session.externalID == CodexSampleTranscript.sessionID)
        #expect(session.cwd == CodexSampleTranscript.cwd)
        #expect(session.projectDirectoryName == CodexSampleTranscript.cwd)
        #expect(session.projectDisplayName == "demo")
        #expect(session.sourceKind == .project)
        #expect(session.fileSize >= CodexSessionScanner.minimumFileSize)
    }

    @Test("Reads Codex session_index thread names as title overrides")
    func readsSessionIndexThreadNames() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let id = "019e648b-1f04-71b0-acb1-9965b3e7f826"

        try writeTranscript(id: id, cwd: "/Users/dev/projects/demo", to: dayDir.appendingPathComponent("rollout-2026-01-10T09-00-00-\(id).jsonl"))
        try TempDir.write(
            [
                #"{"id":"\#(id)","thread_name":"Old title","updated_at":"2026-01-10T09:00:00Z"}"#,
                #"{"id":"\#(id)","thread_name":"梳理问题原因","updated_at":"2026-01-10T09:01:00Z"}"#,
            ].joined(separator: "\n") + "\n",
            to: root.appendingPathComponent("session_index.jsonl")
        )

        let session = try #require(await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan().first)

        #expect(session.titleOverride == "梳理问题原因")
    }

    @Test("Folds Codex worktrees into matching real project groups")
    func foldsWorktreesIntoMatchingProject() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let project = "/Users/dev/projects/demo"
        let worktree = "/Users/dev/.codex/worktrees/abcd/demo"

        try writeTranscript(id: "project-session", cwd: project, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-00-00-project-session.jsonl"))
        try writeTranscript(id: "worktree-session", cwd: worktree, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-01-00-worktree-session.jsonl"))

        let sessions = await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan()
        let worktreeSession = try #require(sessions.first { $0.externalID == "worktree-session" })

        #expect(worktreeSession.cwd == worktree)
        #expect(worktreeSession.projectDirectoryName == project)
        #expect(worktreeSession.projectDisplayName == "demo")
        #expect(worktreeSession.titleFallback == "demo")
        #expect(worktreeSession.sourceKind == .worktree)
    }

    @Test("Folds agent sessions with parents into the parent project")
    func foldsAgentSessionsIntoParentProject() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let parentID = "019d4d6f-f74e-7221-a8cb-142a1fef07bc"
        let childID = "019d4d70-0000-7000-8000-000000000001"
        let project = "/Users/dev/projects/demo"
        let agentCwd = "/Users/dev/.cumora/agents/atlas-6a73"

        try writeTranscript(id: parentID, cwd: project, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-00-00-\(parentID).jsonl"))
        let childMeta = #"{"timestamp":"2026-01-10T09:01:00.000Z","type":"session_meta","payload":{"id":"\#(childID)","cwd":"\#(agentCwd)","thread_source":"subagent","agent_nickname":"Atlas","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\#(parentID)"}}}}}"#
        try writeTranscript(meta: childMeta, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-01-00-\(childID).jsonl"))

        let sessions = await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan()
        let child = try #require(sessions.first { $0.externalID == childID })

        #expect(child.cwd == agentCwd)
        #expect(child.projectDirectoryName == project)
        #expect(child.projectDisplayName == "demo")
        #expect(child.titleFallback == "Atlas")
        #expect(child.sourceKind == .agent)
        #expect(child.agentInfo?.parentSessionID == "codex::\(parentID)")
    }

    @Test("Keeps unresolved agent sessions in an explicit agent group")
    func unresolvedAgentSessionsUseAgentGroup() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let agentCwd = "/Users/dev/.cumora/agents/atlas-6a73"

        try writeTranscript(id: "agent-session", cwd: agentCwd, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-00-00-agent-session.jsonl"))

        let session = try #require(await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan().first)

        #expect(session.projectDirectoryName == "codex::agent-sessions")
        #expect(session.projectDisplayName == "Agent Sessions")
        #expect(session.titleFallback == "Agent session")
        #expect(session.sourceKind == .agent)
    }

    @Test("Groups Documents Codex sessions as ad-hoc sessions with slug fallback titles")
    func groupsDocumentsCodexSessionsAsAdHoc() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let cwd = "/Users/dev/Documents/Codex/2026-05-24/files-mentioned-by-the-user"

        try writeTranscript(id: "ad-hoc-session", cwd: cwd, to: dayDir.appendingPathComponent("rollout-2026-01-10T09-00-00-ad-hoc-session.jsonl"))

        let session = try #require(await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan().first)

        #expect(session.projectDirectoryName == "codex::ad-hoc-sessions")
        #expect(session.projectDisplayName == "Ad-hoc Codex Sessions")
        #expect(session.titleFallback == "files mentioned by the user")
        #expect(session.sourceKind == .adHoc)
    }

    @Test("Reads Codex subagent parent metadata")
    func readsSubagentParentMetadata() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let dayDir = root.appendingPathComponent("sessions/2026/01/10", isDirectory: true)
        let childID = "019d4d70-0000-7000-8000-000000000001"
        let parentID = "019d4d6f-f74e-7221-a8cb-142a1fef07bc"
        let meta = #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"\#(childID)","timestamp":"2026-01-10T09:00:00.000Z","cwd":"/Users/dev/projects/demo","thread_source":"subagent","agent_nickname":"Worker","agent_role":"trellis-implement","agent_path":"/root/worker","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\#(parentID)","depth":1,"agent_path":"/root/worker","agent_nickname":"Worker","agent_role":"trellis-implement"}}}}}"#
        let filler = #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#
        let fileName = "rollout-2026-01-10T09-00-00-\(childID).jsonl"
        try TempDir.write(([meta] + Array(repeating: filler, count: 4)).joined(separator: "\n") + "\n",
                          to: dayDir.appendingPathComponent(fileName))

        let session = try #require(await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan().first)

        #expect(session.agentInfo?.threadSource == "subagent")
        #expect(session.agentInfo?.parentSessionID == "codex::\(parentID)")
        #expect(session.agentInfo?.displayTitle == "Worker / trellis-implement")
    }

    @Test("Returns nothing when the sessions directory is absent")
    func missingDirectory() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let sessions = await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan()
        #expect(sessions.isEmpty)
    }

    private func writeTranscript(id: String, cwd: String, to url: URL) throws {
        let meta = #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","source":"test"}}"#
        try writeTranscript(meta: meta, to: url)
    }

    private func writeTranscript(meta: String, to url: URL) throws {
        let filler = #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"hello"}}"#
        try TempDir.write(([meta] + Array(repeating: filler, count: 4)).joined(separator: "\n") + "\n", to: url)
    }
}
