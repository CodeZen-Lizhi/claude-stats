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
        #expect(session.fileSize >= CodexSessionScanner.minimumFileSize)
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
}
