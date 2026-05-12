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

    @Test("Returns nothing when the sessions directory is absent")
    func missingDirectory() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let sessions = await CodexSessionScanner(paths: CodexPaths(homeDirectory: root)).scan()
        #expect(sessions.isEmpty)
    }
}
