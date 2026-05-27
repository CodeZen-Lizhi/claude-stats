import Foundation

/// Immutable per-million-token pricing table. Loaded once at launch from the
/// bundled `default-pricing.json`, optionally overlaid by a user file at
/// `~/.claude-stats/pricing.json`. Being a value type with only `let`
/// storage it is `Sendable` and safe to use from the off-main parsers.
struct ModelPricing: Sendable, Hashable {
    /// Dollars per 1,000,000 tokens for each token category.
    struct Rates: Sendable, Hashable, Codable {
        struct LongContext: Sendable, Hashable, Codable {
            var thresholdInputTokens: Int
            var input: Double
            var output: Double
            var cacheWrite5m: Double
            var cacheWrite1h: Double
            var cacheRead: Double
        }

        var input: Double
        var output: Double
        var cacheWrite5m: Double
        var cacheWrite1h: Double
        var cacheRead: Double
        var longContext: LongContext? = nil

        /// Derive cache rates from the input rate using conservative defaults
        /// (5m write = 1.25x, 1h write = 2x, read = 0.1x) when a config file
        /// only specifies input/output.
        static func derived(input: Double, output: Double) -> Rates {
            Rates(input: input, output: output,
                  cacheWrite5m: input * 1.25, cacheWrite1h: input * 2.0, cacheRead: input * 0.1)
        }
    }

    let rates: [String: Rates]
    let defaultRate: Rates

    init(rates: [String: Rates], defaultRate: Rates) {
        self.rates = rates
        self.defaultRate = defaultRate
    }

    // MARK: Lookup

    /// Exact match if we have one, otherwise a fuzzy fallback by family
    /// (`gpt` / `codex` / OpenAI reasoning families), otherwise the configured
    /// default.
    func rate(for model: String) -> Rates {
        if let exact = rates[model] { return exact }
        let lower = model.lowercased()
        if let prefixed = rates
            .keys
            .sorted(by: { $0.count > $1.count })
            .first(where: {
                let key = $0.lowercased()
                guard lower.hasPrefix(key + "-") else { return false }
                let suffix = lower.dropFirst(key.count + 1)
                let yearPrefix = suffix.prefix(4)
                return yearPrefix.count == 4 && yearPrefix.allSatisfy(\.isNumber)
            }),
           let r = rates[prefixed] {
            return r
        }
        func first(containing needle: String) -> Rates? {
            rates.first { $0.key.lowercased().contains(needle) }?.value
        }
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("o4") || lower.contains("codex"),
           let r = first(containing: "gpt") { return r }
        return defaultRate
    }

    func hasExactRate(for model: String) -> Bool { rates[model] != nil }

    /// Estimated USD cost for a chunk of usage attributed to `model`.
    func cost(model: String, usage: TokenUsage) -> Double {
        let r = rate(for: model)
        return cost(usage: usage,
                    input: r.input,
                    output: r.output,
                    cacheRead: r.cacheRead,
                    cacheWrite5m: r.cacheWrite5m,
                    cacheWrite1h: r.cacheWrite1h)
    }

    func costEstimate(model: String, usage: TokenUsage) -> CostEstimate {
        CostEstimate(standardAPI: cost(model: model, usage: usage))
    }

    /// Estimated USD cost for one request/turn, using long-context rates when
    /// the raw prompt input for that turn crosses the model's published
    /// threshold.
    func cost(model: String, usage: TokenUsage, contextInputTokens: Int) -> Double {
        let r = rate(for: model)
        if let long = r.longContext, contextInputTokens > long.thresholdInputTokens {
            return cost(usage: usage,
                        input: long.input,
                        output: long.output,
                        cacheRead: long.cacheRead,
                        cacheWrite5m: long.cacheWrite5m,
                        cacheWrite1h: long.cacheWrite1h)
        }
        return cost(model: model, usage: usage)
    }

    private func cost(usage: TokenUsage,
                      input: Double,
                      output: Double,
                      cacheRead: Double,
                      cacheWrite5m: Double,
                      cacheWrite1h: Double) -> Double {
        let perMillion = 1_000_000.0
        return Double(usage.inputTokens) / perMillion * input
            + Double(usage.outputTokens) / perMillion * output
            + Double(usage.cacheReadTokens) / perMillion * cacheRead
            + Double(usage.cacheCreation5mTokens) / perMillion * cacheWrite5m
            + Double(usage.cacheCreation1hTokens) / perMillion * cacheWrite1h
    }

    // MARK: Loading

    private struct File: Codable {
        var _comment: String?
        var models: [String: Rates]
        var defaultPricing: Rates?

        enum CodingKeys: String, CodingKey {
            case _comment = "comment"
            case models
            case defaultPricing = "default_pricing"
        }
    }

    /// Hard-coded last-resort table so the app still works if the bundled
    /// resource is missing.
    static let fallback = ModelPricing(
        rates: [
            "gpt-5.4": Rates.derived(input: 2.5, output: 15),
            "gpt-5": Rates.derived(input: 1.25, output: 10),
            "gpt-5-codex": Rates.derived(input: 1.25, output: 10),
        ],
        defaultRate: Rates.derived(input: 2.5, output: 15)
    )

    /// Load the bundled defaults, then overlay `~/.claude-stats/pricing.json`
    /// if the user has one. Never throws — falls back to ``fallback``.
    static func loadDefault(bundle: Bundle = .main,
                            userFile: URL? = userPricingFileURL()) -> ModelPricing {
        var merged = decode(bundle.url(forResource: "default-pricing", withExtension: "json")) ?? fallback.asFile()
        if let userFile, let user = decode(userFile) {
            merged.models.merge(user.models) { _, override in override }
            if let d = user.defaultPricing { merged.defaultPricing = d }
        }
        return ModelPricing(rates: merged.models, defaultRate: merged.defaultPricing ?? fallback.defaultRate)
    }

    static func userPricingFileURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-stats", isDirectory: true)
            .appendingPathComponent("pricing.json")
    }

    static func writeUserPricing(_ pricing: ModelPricing, to url: URL? = userPricingFileURL()) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = File(
            _comment: "User-edited pricing in USD per 1,000,000 tokens. Restart or rescan Codex Statistics to apply changes to parsed costs.",
            models: pricing.rates,
            defaultPricing: pricing.defaultRate
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private static func decode(_ url: URL?) -> File? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    private func asFile() -> File { File(_comment: nil, models: rates, defaultPricing: defaultRate) }
}
