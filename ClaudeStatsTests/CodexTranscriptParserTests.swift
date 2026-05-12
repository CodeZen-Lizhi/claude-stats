import Testing
import Foundation
@testable import ClaudeStats

@Suite("CodexTranscriptParser")
struct CodexTranscriptParserTests {

    private func parseSample() async throws -> SessionStats {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(CodexSampleTranscript.text, to: url)
        let stats = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .parse(transcriptAt: url, fallbackTitle: "fallback")
        return try #require(stats)
    }

    @Test("Sums turn deltas per model, splitting cached input tokens out")
    func tokenTotals() async throws {
        let stats = try await parseSample()
        #expect(stats.models.count == 1)
        let m = try #require(stats.models.first)
        #expect(m.model == CodexSampleTranscript.model)
        // delta1: input 1100 (1000 cached → 100 uncached), output 200
        // delta2: input 300 (100 cached → 200 uncached), output 50
        #expect(m.usage.inputTokens == 300)
        #expect(m.usage.outputTokens == 250)
        #expect(m.usage.cacheReadTokens == 1100)
        #expect(m.usage.total == 1650)
        // cost = 300/1e6*10 + 250/1e6*20 + 1100/1e6*1
        #expect(abs(m.estimatedCost - (0.003 + 0.005 + 0.0011)) < 1e-9)
    }

    @Test("Counts user + agent messages, prefers thread name as title")
    func messagesAndTitle() async throws {
        let stats = try await parseSample()
        #expect(stats.messageCount == 4)
        #expect(stats.title == CodexSampleTranscript.threadName)
    }

    @Test("First/last activity span the transcript; timeline has one bucket per hour")
    func activityWindow() async throws {
        let stats = try await parseSample()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        #expect(stats.firstActivity == (try iso.parse("2026-01-10T09:00:00.000Z")))
        #expect(stats.lastActivity == (try iso.parse("2026-01-10T10:31:00.000Z")))
        #expect(stats.timeline.count == 2)
        #expect(stats.activityIntervals.count == 2)
    }

    @Test("Empty / metadata-only transcript yields nil")
    func emptyTranscript() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(#"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"/tmp"}}"# + "\n", to: url)
        let stats = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .parse(transcriptAt: url, fallbackTitle: "fallback")
        #expect(stats == nil)
    }
}
