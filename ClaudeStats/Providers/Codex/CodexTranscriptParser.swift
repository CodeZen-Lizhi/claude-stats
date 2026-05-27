import Foundation

/// Parses an OpenAI Codex CLI `rollout-*.jsonl` transcript into ``SessionStats``.
///
/// Codex records a `token_count` event after each turn carrying both the
/// cumulative usage (`total_token_usage`) and that turn's delta
/// (`last_token_usage`). We attribute each delta to the model in effect at the
/// time (the most recent `turn_context.model`), which also gives an hourly
/// per-model timeline. Cache-hit prompt tokens are reported as
/// `cached_input_tokens`, a subset of `input_tokens`.
struct CodexTranscriptParser: Sendable {
    let pricing: ModelPricing

    /// Codex sessions don't name the model in `session_meta`; default to GPT-5
    /// when no `turn_context` has been seen yet.
    private static let defaultModel = "gpt-5"
    private static let lineReadChunkSize = 64 * 1024

    func parse(transcriptAt url: URL, fallbackTitle: String, sessionID: String? = nil) async -> SessionStats? {
        var currentModel = Self.defaultModel
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        var billableMessages: [BillableMessage] = []
        var tokenEventIndex = 0
        var messageCount = 0
        var firstActivity: Date?
        var lastActivity: Date?
        var threadName: String?
        var firstUserTitle: String?
        var messageTimestamps: [Date] = []
        let calendar = Calendar.current

        let decoder = JSONDecoder()
        let parsedByteCount = Self.readLines(from: url) { lineData in
            guard let line = try? decoder.decode(CodexLine.self, from: lineData) else { return }
            let date = ISO8601.parse(line.timestamp)
            track(date, &firstActivity, &lastActivity)
            guard let payload = line.payload else { return }

            switch (line.type, payload.type) {
            case ("turn_context", _):
                if let m = payload.model, !m.isEmpty { currentModel = m }
                else if let m = payload.collaborationMode?.settings?.model, !m.isEmpty { currentModel = m }

            case ("event_msg", "thread_name_updated"):
                if let t = payload.threadName?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    threadName = t
                }

            case ("event_msg", "agent_message"):
                messageCount += 1
                if let date { messageTimestamps.append(date) }

            case ("event_msg", "user_message"):
                messageCount += 1
                if let date { messageTimestamps.append(date) }
                if firstUserTitle == nil, let raw = payload.message, let cleaned = TitleSanitizer.sanitize(raw) {
                    firstUserTitle = cleaned
                }

            case ("event_msg", "token_count"):
                guard let delta = payload.info?.lastTokenUsage else { break }
                let usage = delta.tokenUsage
                guard usage.total > 0 else { break }
                var acc = perModel[currentModel] ?? (0, .zero, .zero)
                acc.count += 1
                acc.usage += usage
                let cost = pricing.cost(
                    model: currentModel,
                    usage: usage,
                    contextInputTokens: delta.rawInputTokens
                )
                let costEstimate = CostEstimate(standardAPI: cost)
                acc.cost += costEstimate
                perModel[currentModel] = acc
                let eventKey = Self.billableEventKey(
                    sessionID: sessionID ?? url.deletingPathExtension().lastPathComponent,
                    sequenceIndex: tokenEventIndex,
                    timestamp: date
                )
                billableMessages.append(BillableMessage(
                    hash: eventKey,
                    model: currentModel,
                    usage: usage,
                    cost: costEstimate,
                    timestamp: date
                ))
                tokenEventIndex += 1
                if let date {
                    let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? calendar.startOfDay(for: date)
                    perModelHourly[currentModel, default: [:]][hour, default: .zero] += usage
                }

            default:
                break
            }
        }
        guard parsedByteCount != nil else { return nil }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timeline = perModelHourly
            .flatMap { model, byHour in byHour.map { ModelBucket(model: model, start: $0.key, usage: $0.value) } }
            .sorted { $0.start < $1.start }

        guard messageCount > 0 || !models.isEmpty else { return nil }

        let title = threadName ?? firstUserTitle ?? fallbackTitle
        return SessionStats(
            title: title,
            messageCount: messageCount,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            models: models,
            timeline: timeline,
            activityIntervals: Self.coalesceBursts(messageTimestamps),
            billableMessages: billableMessages,
            lastModel: currentModel
        )
    }

    func parseUsageAppend(transcriptAt url: URL, session: Session, state: UsageLedgerParseState) async -> UsageLedgerAppendResult? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.lastParsedByteOffset)
        } catch {
            return nil
        }

        var currentModel = state.lastModel ?? Self.defaultModel
        var events: [UsageLedgerEvent] = []
        var tokenEventIndex = state.eventCount
        var messageCountDelta = 0
        var firstActivity: Date?
        var lastActivity: Date?
        var threadName: String?
        var firstUserTitle: String?
        let decoder = JSONDecoder()

        let parsedByteCount = Self.readLines(
            from: handle,
            requireTrailingNewline: true,
            startingAt: state.lastParsedByteOffset
        ) { lineData in
            guard let line = try? decoder.decode(CodexLine.self, from: lineData) else { return }
            let date = ISO8601.parse(line.timestamp)
            track(date, &firstActivity, &lastActivity)
            guard let payload = line.payload else { return }

            switch (line.type, payload.type) {
            case ("turn_context", _):
                if let m = payload.model, !m.isEmpty { currentModel = m }
                else if let m = payload.collaborationMode?.settings?.model, !m.isEmpty { currentModel = m }

            case ("event_msg", "thread_name_updated"):
                if let t = payload.threadName?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    threadName = t
                }

            case ("event_msg", "agent_message"):
                messageCountDelta += 1

            case ("event_msg", "user_message"):
                messageCountDelta += 1
                if firstUserTitle == nil, let raw = payload.message, let cleaned = TitleSanitizer.sanitize(raw) {
                    firstUserTitle = cleaned
                }

            case ("event_msg", "token_count"):
                guard let delta = payload.info?.lastTokenUsage else { break }
                let usage = delta.tokenUsage
                guard usage.total > 0, let date else { break }
                let cost = pricing.cost(
                    model: currentModel,
                    usage: usage,
                    contextInputTokens: delta.rawInputTokens
                )
                let eventKey = Self.billableEventKey(
                    sessionID: session.id,
                    sequenceIndex: tokenEventIndex,
                    timestamp: date
                )
                events.append(UsageLedgerEvent(
                    eventKey: eventKey,
                    sessionID: session.id,
                    provider: session.provider,
                    model: currentModel,
                    timestamp: date,
                    usage: usage,
                    cost: CostEstimate(standardAPI: cost),
                    sourcePath: session.filePath,
                    sequenceIndex: tokenEventIndex,
                    parentSessionID: session.agentInfo?.parentSessionID
                ))
                tokenEventIndex += 1

            default:
                break
            }
        }
        guard let parsedByteCount else { return nil }

        guard parsedByteCount > 0 else {
            return UsageLedgerAppendResult(
                events: [],
                lastParsedByteOffset: state.lastParsedByteOffset,
                messageCountDelta: 0,
                firstActivity: nil,
                lastActivity: nil,
                title: nil,
                lastModel: state.lastModel
            )
        }

        return UsageLedgerAppendResult(
            events: events,
            lastParsedByteOffset: state.lastParsedByteOffset + parsedByteCount,
            messageCountDelta: messageCountDelta,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            title: threadName ?? firstUserTitle,
            lastModel: currentModel
        )
    }

    func messages(transcriptAt url: URL) async -> [SessionTranscriptMessage] {
        var messages: [SessionTranscriptMessage] = []
        let decoder = JSONDecoder()
        var lineIndex = 0
        let parsedByteCount = Self.readLines(from: url) { lineData in
            defer { lineIndex += 1 }
            guard let line = try? decoder.decode(CodexLine.self, from: lineData),
                  line.type == "event_msg",
                  let payload = line.payload else { return }

            let role: SessionTranscriptMessage.Role
            switch payload.type {
            case "user_message":
                role = .user
            case "agent_message":
                role = .assistant
            default:
                return
            }

            guard let text = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }

            messages.append(SessionTranscriptMessage(
                id: "codex-\(lineIndex)",
                role: role,
                text: text,
                timestamp: ISO8601.parse(line.timestamp),
                model: nil
            ))
        }
        guard parsedByteCount != nil else { return [] }

        return messages
    }

    func taskIntervals(transcriptAt url: URL) async -> [SessionTaskInterval] {
        struct Started {
            let id: String
            let start: Date
        }

        var open: [String: Started] = [:]
        var intervals: [SessionTaskInterval] = []
        let decoder = JSONDecoder()
        let parsedByteCount = Self.readLines(from: url) { lineData in
            guard let line = try? decoder.decode(CodexLine.self, from: lineData),
                  line.type == "event_msg",
                  let payload = line.payload,
                  let turnID = payload.turnID else { return }

            switch payload.type {
            case "task_started":
                let start = payload.startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? ISO8601.parse(line.timestamp)
                if let start {
                    open[turnID] = Started(id: turnID, start: start)
                }
            case "task_complete":
                guard let started = open.removeValue(forKey: turnID) else { return }
                let end = payload.completedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? ISO8601.parse(line.timestamp)
                    ?? started.start
                intervals.append(SessionTaskInterval(id: started.id, start: started.start, end: max(end, started.start)))
            default:
                return
            }
        }
        guard parsedByteCount != nil else { return [] }

        return intervals
    }

    @discardableResult
    private static func readLines(
        from url: URL,
        requireTrailingNewline: Bool = false,
        handleLine: (Data) -> Void
    ) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return readLines(from: handle, requireTrailingNewline: requireTrailingNewline, startingAt: 0, handleLine: handleLine)
    }

    @discardableResult
    private static func readLines(
        from handle: FileHandle,
        requireTrailingNewline: Bool,
        startingAt offset: UInt64,
        handleLine: (Data) -> Void
    ) -> UInt64? {
        do {
            try handle.seek(toOffset: offset)
            var buffer = Data()
            var parsedBytes: UInt64 = 0
            while true {
                guard let chunk = try handle.read(upToCount: lineReadChunkSize) else { break }
                guard !chunk.isEmpty else { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    if newline > buffer.startIndex {
                        handleLine(Data(buffer[..<newline]))
                    }
                    let nextIndex = buffer.index(after: newline)
                    parsedBytes += UInt64(buffer.distance(from: buffer.startIndex, to: nextIndex))
                    buffer.removeSubrange(buffer.startIndex..<nextIndex)
                }
            }
            if !requireTrailingNewline, !buffer.isEmpty {
                handleLine(buffer)
                parsedBytes += UInt64(buffer.count)
            }
            return parsedBytes
        } catch {
            return nil
        }
    }

    private func track(_ date: Date?, _ first: inout Date?, _ last: inout Date?) {
        guard let date else { return }
        if first == nil || date < first! { first = date }
        if last == nil || date > last! { last = date }
    }

    /// Adjacent message timestamps within ``burstGap`` collapse into one
    /// interval; short runs are widened so they stay visible on timelines.
    private static let burstGap: TimeInterval = 5 * 60
    private static let minBurst: TimeInterval = 30

    static func coalesceBursts(_ timestamps: [Date]) -> [DateInterval] {
        let sorted = timestamps.sorted()
        guard let first = sorted.first else { return [] }
        var out: [DateInterval] = []
        var start = first
        var end = first
        for t in sorted.dropFirst() {
            if t.timeIntervalSince(end) <= burstGap {
                end = max(end, t)
            } else {
                out.append(burstInterval(start, end))
                start = t
                end = t
            }
        }
        out.append(burstInterval(start, end))
        return out
    }

    private static func burstInterval(_ start: Date, _ end: Date) -> DateInterval {
        end.timeIntervalSince(start) >= minBurst
            ? DateInterval(start: start, end: end)
            : DateInterval(start: start, duration: minBurst)
    }

    private static func billableEventKey(sessionID: String, sequenceIndex: Int, timestamp: Date?) -> String {
        let millis = timestamp.map { Int(($0.timeIntervalSince1970 * 1_000).rounded()) } ?? -1
        return "codex|\(sessionID)|\(sequenceIndex)|\(millis)"
    }
}

// MARK: - JSONL line shapes (only the fields we read)

private struct CodexLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?          // inner event type for `event_msg`
        let model: String?         // `turn_context`
        let collaborationMode: CollaborationMode?
        let threadName: String?    // `thread_name_updated`
        let message: String?       // `user_message` / `agent_message`
        let info: TokenInfo?       // `token_count` (may be null)
        let turnID: String?
        let startedAt: Int?
        let completedAt: Int?

        enum CodingKeys: String, CodingKey {
            case type, model, message, info
            case collaborationMode = "collaboration_mode"
            case threadName = "thread_name"
            case turnID = "turn_id"
            case startedAt = "started_at"
            case completedAt = "completed_at"
        }
    }

    struct CollaborationMode: Decodable {
        let settings: Settings?
        struct Settings: Decodable { let model: String? }
    }

    struct TokenInfo: Decodable {
        let lastTokenUsage: Usage?
        let totalTokenUsage: Usage?
        enum CodingKeys: String, CodingKey {
            case lastTokenUsage = "last_token_usage"
            case totalTokenUsage = "total_token_usage"
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
        }

        /// Codex `input_tokens` includes the cache-hit portion; split it out so
        /// the cached tokens are priced at the read rate, not the input rate.
        var tokenUsage: TokenUsage {
            let cached = cachedInputTokens ?? 0
            let input = max(0, rawInputTokens - cached)
            return TokenUsage(
                inputTokens: input,
                outputTokens: outputTokens ?? 0,
                cacheReadTokens: cached,
                cacheCreation5mTokens: 0,
                cacheCreation1hTokens: 0
            )
        }

        var rawInputTokens: Int { inputTokens ?? 0 }
    }
}

private enum ISO8601 {
    static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let withoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = try? withFraction.parse(string) { return d }
        return try? withoutFraction.parse(string)
    }
}
