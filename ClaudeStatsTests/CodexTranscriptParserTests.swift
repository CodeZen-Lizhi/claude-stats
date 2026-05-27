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

    private func parseLines(_ lines: [String], pricing: ModelPricing) async throws -> SessionStats {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(lines.joined(separator: "\n") + "\n", to: url)
        let stats = await CodexTranscriptParser(pricing: pricing)
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

    @Test("Codex cache rate uses cached input over total prompt input")
    func codexCacheRate() async throws {
        let stats = try await parseSample()
        let usage = try #require(stats.models.first?.usage)
        let provider = CodexProvider(
            paths: CodexPaths(homeDirectory: URL(fileURLWithPath: "/tmp/codex-test", isDirectory: true)),
            pricing: CodexSampleTranscript.pricing
        )

        let rate = try #require(provider.cacheHitRate(for: usage))
        #expect(abs(rate - (1100.0 / 1400.0)) < 1e-9)
    }

    @Test("Applies GPT-5.4 long-context pricing per turn")
    func gpt54LongContextCostPerTurn() async throws {
        let stats = try await parseLines(Self.gpt54TranscriptLines([
            (timestamp: "2026-01-10T09:00:08.000Z", input: 1_000, cached: 200, output: 100),
            (timestamp: "2026-01-10T09:01:08.000Z", input: 272_001, cached: 100_000, output: 100),
        ]), pricing: Self.gpt54Pricing)

        let model = try #require(stats.models.first)
        #expect(model.model == "gpt-5.4")
        #expect(model.usage.inputTokens == 172_801)
        #expect(model.usage.outputTokens == 200)
        #expect(model.usage.cacheReadTokens == 100_200)
        #expect(model.usage.total == 273_201)

        let shortCost = (800.0 / 1_000_000.0 * 2.5)
            + (100.0 / 1_000_000.0 * 15.0)
            + (200.0 / 1_000_000.0 * 0.25)
        let longCost = (172_001.0 / 1_000_000.0 * 5.0)
            + (100.0 / 1_000_000.0 * 22.5)
            + (100_000.0 / 1_000_000.0 * 0.5)
        #expect(abs(model.estimatedCost - (shortCost + longCost)) < 1e-9)
    }

    @Test("Aggregate GPT-5.4 usage does not trigger long-context pricing")
    func aggregateUsageDoesNotTriggerLongContextPricing() async throws {
        let stats = try await parseLines(Self.gpt54TranscriptLines([
            (timestamp: "2026-01-10T09:00:08.000Z", input: 200_000, cached: 0, output: 0),
            (timestamp: "2026-01-10T09:01:08.000Z", input: 200_000, cached: 0, output: 0),
        ]), pricing: Self.gpt54Pricing)

        let model = try #require(stats.models.first)
        #expect(model.usage.inputTokens == 400_000)
        #expect(abs(model.estimatedCost - 1.0) < 1e-9)
    }

    @Test("Counts user + agent messages, prefers thread name as title")
    func messagesAndTitle() async throws {
        let stats = try await parseSample()
        #expect(stats.messageCount == 4)
        #expect(stats.title == CodexSampleTranscript.threadName)
    }

    @Test("Codex provider prefers session index title override")
    func providerPrefersSessionIndexTitleOverride() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write([
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"indexed-session","cwd":"/tmp/project"}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"我反馈一些项目的问题"}}"#,
        ].joined(separator: "\n") + "\n", to: url)
        let session = Session(
            id: "codex::indexed-session",
            externalID: "indexed-session",
            provider: .codex,
            projectDirectoryName: "/tmp/project",
            filePath: url.path,
            cwd: "/tmp/project",
            titleOverride: "梳理问题原因",
            lastModified: Date(timeIntervalSince1970: 1_768_035_600),
            fileSize: Int64((try Data(contentsOf: url)).count)
        )

        let stats = try #require(await CodexProvider(
            paths: CodexPaths(homeDirectory: root),
            pricing: CodexSampleTranscript.pricing
        ).parse(session))

        #expect(stats.title == "梳理问题原因")
    }

    @Test("Uses fallback title when transcript has no thread name or user title")
    func fallbackTitleWhenTranscriptHasNoDisplayTitle() async throws {
        let stats = try await parseLines([
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"agent-session","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"agent_message","message":"working"}}"#,
        ], pricing: CodexSampleTranscript.pricing)

        #expect(stats.title == "fallback")
    }

    @Test("Extracts displayable conversation messages")
    func displayMessages() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try TempDir.write(CodexSampleTranscript.text, to: url)

        let messages = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .messages(transcriptAt: url)

        #expect(messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(messages.map(\.text) == ["please refactor the parser", "on it", "more please", "sure"])
        #expect(messages.first?.timestamp == (try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-01-10T09:00:02.000Z")))
    }

    @Test("Extracts task intervals for subagent attribution")
    func taskIntervals() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"parent","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-01-10T09:01:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","started_at":1768035660,"model_context_window":258400}}"#,
            #"{"timestamp":"2026-01-10T09:04:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1768035840,"duration_ms":180000}}"#,
        ]
        try TempDir.write(lines.joined(separator: "\n") + "\n", to: url)

        let intervals = await CodexTranscriptParser(pricing: CodexSampleTranscript.pricing)
            .taskIntervals(transcriptAt: url)

        let interval = try #require(intervals.first)
        #expect(intervals.count == 1)
        #expect(interval.id == "turn-1")
        #expect(interval.start == Date(timeIntervalSince1970: 1_768_035_660))
        #expect(interval.end == Date(timeIntervalSince1970: 1_768_035_840))
    }

    @Test("Parses appended usage from previous offset and model state")
    func appendedUsageUsesPreviousOffsetAndModel() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        let initial = [
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"append-session","cwd":"/tmp/project"}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-01-10T09:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"hello"}}"#,
        ].joined(separator: "\n") + "\n"
        try Self.write(initial, to: url)
        let offset = UInt64((try Data(contentsOf: url)).count)
        let appended = [
            #"{"timestamp":"2026-01-10T09:00:03.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hi"}}"#,
            #"{"timestamp":"2026-01-10T09:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":130}}}}"#,
        ].joined(separator: "\n") + "\n"
        try FileHandle(forWritingTo: url).closeAfter {
            try $0.seekToEnd()
            $0.write(Data(appended.utf8))
        }
        let session = Session(
            id: "codex::append-session",
            externalID: "append-session",
            provider: .codex,
            projectDirectoryName: "project",
            filePath: url.path,
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_768_035_604),
            fileSize: Int64((try Data(contentsOf: url)).count)
        )
        let state = UsageLedgerParseState(
            sessionID: session.id,
            provider: session.provider,
            sourcePath: session.filePath,
            fileSize: Int64(offset),
            lastModified: Date(timeIntervalSince1970: 1_768_035_602),
            lastParsedByteOffset: offset,
            eventCount: 1,
            title: "Existing",
            messageCount: 1,
            firstActivity: Date(timeIntervalSince1970: 1_768_035_600),
            lastActivity: Date(timeIntervalSince1970: 1_768_035_602),
            sourceExists: true,
            lastSeenAt: Date(timeIntervalSince1970: 1_768_035_602),
            lastModel: "gpt-5.4"
        )

        let result = try #require(await CodexTranscriptParser(pricing: Self.gpt54Pricing)
            .parseUsageAppend(transcriptAt: url, session: session, state: state))
        let event = try #require(result.events.first)

        #expect(result.events.count == 1)
        #expect(result.messageCountDelta == 1)
        #expect(result.lastParsedByteOffset == UInt64(max(session.fileSize, 0)))
        #expect(result.lastModel == "gpt-5.4")
        #expect(event.sequenceIndex == 1)
        #expect(event.model == "gpt-5.4")
        #expect(event.usage.inputTokens == 80)
        #expect(event.usage.cacheReadTokens == 20)
        #expect(event.usage.outputTokens == 30)
    }

    @Test("Empty appended range advances parse state without adding events")
    func emptyAppendRangeAdvancesOffset() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        try Self.write(#"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"empty-append","cwd":"/tmp/project"}}"# + "\n", to: url)
        let size = Int64((try Data(contentsOf: url)).count)
        let session = Session(
            id: "codex::empty-append",
            externalID: "empty-append",
            provider: .codex,
            projectDirectoryName: "project",
            filePath: url.path,
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_768_035_600),
            fileSize: size
        )
        let state = UsageLedgerParseState(
            sessionID: session.id,
            provider: session.provider,
            sourcePath: session.filePath,
            fileSize: size,
            lastModified: session.lastModified,
            lastParsedByteOffset: UInt64(max(size, 0)),
            eventCount: 0,
            title: nil,
            messageCount: 0,
            firstActivity: nil,
            lastActivity: nil,
            sourceExists: true,
            lastSeenAt: session.lastModified,
            lastModel: "gpt-5.4"
        )

        let result = try #require(await CodexTranscriptParser(pricing: Self.gpt54Pricing)
            .parseUsageAppend(transcriptAt: url, session: session, state: state))

        #expect(result.events.isEmpty)
        #expect(result.messageCountDelta == 0)
        #expect(result.lastParsedByteOffset == UInt64(max(size, 0)))
        #expect(result.lastModel == "gpt-5.4")
    }

    @Test("Append parser leaves incomplete trailing JSONL line for the next scan")
    func appendParserLeavesIncompleteTrailingLine() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        let initial = #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"partial-append","cwd":"/tmp/project"}}"# + "\n"
        try Self.write(initial, to: url)
        let offset = UInt64((try Data(contentsOf: url)).count)
        let completeLine = #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hi"}}"# + "\n"
        let partialLine = #"{"timestamp":"2026-01-10T09:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100"#
        try FileHandle(forWritingTo: url).closeAfter {
            try $0.seekToEnd()
            $0.write(Data((completeLine + partialLine).utf8))
        }
        let session = Session(
            id: "codex::partial-append",
            externalID: "partial-append",
            provider: .codex,
            projectDirectoryName: "project",
            filePath: url.path,
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_768_035_602),
            fileSize: Int64((try Data(contentsOf: url)).count)
        )
        let state = UsageLedgerParseState(
            sessionID: session.id,
            provider: session.provider,
            sourcePath: session.filePath,
            fileSize: Int64(offset),
            lastModified: Date(timeIntervalSince1970: 1_768_035_600),
            lastParsedByteOffset: offset,
            eventCount: 0,
            title: nil,
            messageCount: 0,
            firstActivity: nil,
            lastActivity: nil,
            sourceExists: true,
            lastSeenAt: Date(timeIntervalSince1970: 1_768_035_600),
            lastModel: "gpt-5.4"
        )

        let result = try #require(await CodexTranscriptParser(pricing: Self.gpt54Pricing)
            .parseUsageAppend(transcriptAt: url, session: session, state: state))

        #expect(result.events.isEmpty)
        #expect(result.messageCountDelta == 1)
        #expect(result.lastParsedByteOffset == offset + UInt64(Data(completeLine.utf8).count))
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

    private static let gpt54Pricing = ModelPricing(
        rates: [
            "gpt-5.4": ModelPricing.Rates(
                input: 2.5,
                output: 15.0,
                cacheWrite5m: 2.5,
                cacheWrite1h: 2.5,
                cacheRead: 0.25,
                longContext: ModelPricing.Rates.LongContext(
                    thresholdInputTokens: 272_000,
                    input: 5.0,
                    output: 22.5,
                    cacheWrite5m: 5.0,
                    cacheWrite1h: 5.0,
                    cacheRead: 0.5
                )
            ),
        ],
        defaultRate: ModelPricing.Rates(input: 1, output: 2, cacheWrite5m: 1, cacheWrite1h: 1, cacheRead: 1)
    )

    private static func gpt54TranscriptLines(_ turns: [(timestamp: String, input: Int, cached: Int, output: Int)]) -> [String] {
        var lines = [
            #"{"timestamp":"2026-01-10T09:00:00.000Z","type":"session_meta","payload":{"id":"long-context","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-01-10T09:00:01.000Z","type":"turn_context","payload":{"turn_id":"t1","cwd":"/tmp","model":"gpt-5.4"}}"#,
        ]
        for turn in turns {
            lines.append(#"{"timestamp":"\#(turn.timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(turn.input),"cached_input_tokens":\#(turn.cached),"output_tokens":\#(turn.output),"reasoning_output_tokens":0,"total_tokens":\#(turn.input + turn.output)}}}}"#)
        }
        return lines
    }

    private static func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-parser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}

private extension FileHandle {
    func closeAfter(_ body: (FileHandle) throws -> Void) throws {
        defer { try? close() }
        try body(self)
    }
}
