import Foundation

/// Immutable per-million-token pricing table. Loaded once at launch from the
/// bundled `default-pricing.json`, optionally overlaid by a user file at
/// `~/.claude-stats/pricing.json`. Being a value type with only `let`
/// storage it is `Sendable` and safe to use from the off-main parsers.
struct ModelPricing: Sendable, Hashable {
    /// Dollars per 1,000,000 tokens for each token category.
    struct Rates: Sendable, Hashable, Codable {
        var input: Double
        var output: Double
        var cacheWrite5m: Double
        var cacheWrite1h: Double
        var cacheRead: Double

        /// Derive cache rates from the input rate using Anthropic's ratios
        /// (5m write = 1.25×, 1h write = 2×, read = 0.1×) when a config file
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
    /// (`opus` / `sonnet` / `haiku` / `gpt` / `gemini`), otherwise the
    /// configured default.
    func rate(for model: String) -> Rates {
        if let exact = rates[model] { return exact }
        let lower = model.lowercased()
        func first(containing needle: String) -> Rates? {
            rates.first { $0.key.lowercased().contains(needle) }?.value
        }
        if lower.contains("opus"), let r = first(containing: "opus") { return r }
        if lower.contains("haiku"), let r = first(containing: "haiku") { return r }
        if lower.contains("sonnet"), let r = first(containing: "sonnet") { return r }
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("codex"),
           let r = first(containing: "gpt") { return r }
        if lower.contains("gemini"), let r = first(containing: "gemini") { return r }
        return defaultRate
    }

    func hasExactRate(for model: String) -> Bool { rates[model] != nil }

    /// Estimated USD cost for a chunk of usage attributed to `model`.
    func cost(model: String, usage: TokenUsage) -> Double {
        let r = rate(for: model)
        let perMillion = 1_000_000.0
        return Double(usage.inputTokens) / perMillion * r.input
            + Double(usage.outputTokens) / perMillion * r.output
            + Double(usage.cacheReadTokens) / perMillion * r.cacheRead
            + Double(usage.cacheCreation5mTokens) / perMillion * r.cacheWrite5m
            + Double(usage.cacheCreation1hTokens) / perMillion * r.cacheWrite1h
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
            "claude-opus-4-7": Rates.derived(input: 15, output: 75),
            "claude-sonnet-4-6": Rates.derived(input: 3, output: 15),
            "claude-haiku-4-5": Rates.derived(input: 1, output: 5),
        ],
        defaultRate: Rates.derived(input: 3, output: 15)
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

    private static func decode(_ url: URL?) -> File? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    private func asFile() -> File { File(_comment: nil, models: rates, defaultPricing: defaultRate) }
}
