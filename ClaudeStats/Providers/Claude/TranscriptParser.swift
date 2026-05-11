import Foundation

/// Parses a Claude Code `.jsonl` transcript into ``SessionStats``: title,
/// message count, activity window, per-model token totals (priced), and a
/// per-day token breakdown.
///
/// Reads the file whole and splits on newlines — transcripts are typically
/// small. (A pathologically huge transcript would be loaded fully into
/// memory; acceptable for v0.1.)
struct TranscriptParser: Sendable {
    let pricing: ModelPricing

    func parse(transcriptAt url: URL, fallbackTitle: String) async -> SessionStats? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var perModel: [String: (count: Int, usage: TokenUsage)] = [:]
        var daily: [Date: TokenUsage] = [:]
        var messageCount = 0
        var firstActivity: Date?
        var lastActivity: Date?
        var aiTitle: String?
        var firstUserTitle: String?
        let calendar = Calendar.current

        let decoder = JSONDecoder()
        for lineBytes in data.split(separator: 0x0A /* \n */, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(TranscriptLine.self, from: Data(lineBytes)) else { continue }
            switch line.type {
            case "ai-title":
                if let t = line.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    aiTitle = t
                }

            case "assistant":
                messageCount += 1
                let date = ISO8601.parse(line.timestamp)
                track(date, &firstActivity, &lastActivity)
                let model = line.message?.model ?? "unknown"
                let usage = line.message?.usage?.tokenUsage ?? .zero
                if usage.total > 0 {
                    var acc = perModel[model] ?? (0, .zero)
                    acc.count += 1
                    acc.usage += usage
                    perModel[model] = acc
                    if let date {
                        daily[calendar.startOfDay(for: date), default: .zero] += usage
                    }
                } else {
                    // Still count the model so a session with assistant turns
                    // but zero recorded usage doesn't vanish.
                    var acc = perModel[model] ?? (0, .zero)
                    acc.count += 1
                    perModel[model] = acc
                }

            case "user":
                messageCount += 1
                track(ISO8601.parse(line.timestamp), &firstActivity, &lastActivity)
                if firstUserTitle == nil, case .text(let raw)? = line.message?.content,
                   let cleaned = TitleSanitizer.sanitize(raw) {
                    firstUserTitle = cleaned
                }

            default:
                break
            }
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, pricing: pricing) }
            .sorted { $0.usage.total > $1.usage.total }
        let daySlices = daily.map { DaySlice(day: $0.key, usage: $0.value) }.sorted { $0.day < $1.day }

        // Empty transcript (only queue-ops / snapshots): not worth showing.
        guard messageCount > 0 || !models.isEmpty else { return nil }

        let title = aiTitle ?? firstUserTitle ?? fallbackTitle
        return SessionStats(
            title: title,
            messageCount: messageCount,
            firstActivity: firstActivity,
            lastActivity: lastActivity,
            models: models,
            daily: daySlices
        )
    }

    private func track(_ date: Date?, _ first: inout Date?, _ last: inout Date?) {
        guard let date else { return }
        if first == nil || date < first! { first = date }
        if last == nil || date > last! { last = date }
    }
}

// MARK: - JSONL line shapes (only the fields we read)

private struct TranscriptLine: Decodable {
    let type: String?
    let timestamp: String?
    let aiTitle: String?
    let message: Message?

    struct Message: Decodable {
        let model: String?
        let usage: Usage?
        let content: Content?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreation: CacheCreation?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
        }

        var tokenUsage: TokenUsage {
            let fiveM = cacheCreation?.ephemeral5m ?? 0
            let oneH = cacheCreation?.ephemeral1h ?? 0
            // Prefer the 5m/1h breakdown. If it's absent, attribute the
            // lump-sum `cache_creation_input_tokens` to the 5m bucket so the
            // tokens aren't lost (and aren't double-counted with the breakdown).
            let (c5, c1) = (fiveM > 0 || oneH > 0) ? (fiveM, oneH) : (cacheCreationInputTokens ?? 0, 0)
            return TokenUsage(
                inputTokens: inputTokens ?? 0,
                outputTokens: outputTokens ?? 0,
                cacheReadTokens: cacheReadInputTokens ?? 0,
                cacheCreation5mTokens: c5,
                cacheCreation1hTokens: c1
            )
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?
        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }

    /// `message.content` is a string for plain prompts, or an array of
    /// content blocks otherwise. We only need to recover a string prompt.
    enum Content: Decodable {
        case text(String)
        case blocks
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { self = .text(s) } else { self = .blocks }
        }
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
