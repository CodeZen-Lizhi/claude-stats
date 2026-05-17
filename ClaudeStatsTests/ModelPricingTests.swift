import Testing
import Foundation
@testable import ClaudeStats

@Suite("ModelPricing")
struct ModelPricingTests {

    @Test("Exact match wins over fuzzy fallback")
    func exactMatch() {
        let rate = ModelPricing.fallback.rate(for: "claude-opus-4-7")
        #expect(rate.input == 15)
        #expect(rate.output == 75)
        #expect(ModelPricing.fallback.hasExactRate(for: "claude-opus-4-7"))
    }

    @Test("Unknown Sonnet variant falls back to a sonnet rate")
    func fuzzySonnet() {
        let rate = ModelPricing.fallback.rate(for: "claude-3-5-sonnet-20241022")
        #expect(rate.input == 3) // claude-sonnet-4-6 in the fallback table
        #expect(!ModelPricing.fallback.hasExactRate(for: "claude-3-5-sonnet-20241022"))
    }

    @Test("Unknown family uses the default rate")
    func unknownFamilyUsesDefault() {
        let rate = ModelPricing.fallback.rate(for: "some-llm-we-have-never-seen")
        #expect(rate == ModelPricing.fallback.defaultRate)
    }

    @Test("Cost is linear in tokens per category")
    func costArithmetic() {
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
        #expect(abs(TestPricing.table.cost(model: "model-a", usage: usage) - 10) < 1e-9)

        let mixed = TokenUsage(inputTokens: 100, outputTokens: 200, cacheReadTokens: 1000,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
        // 100/1e6*10 + 200/1e6*20 + 1000/1e6*1 = 0.001 + 0.004 + 0.001
        #expect(abs(TestPricing.table.cost(model: "model-a", usage: mixed) - 0.006) < 1e-9)
    }

    @Test("Long context rates are selected only above the threshold")
    func longContextCostSelection() {
        let pricing = ModelPricing(
            rates: [
                "model-long": ModelPricing.Rates(
                    input: 10,
                    output: 20,
                    cacheWrite5m: 10,
                    cacheWrite1h: 10,
                    cacheRead: 1,
                    longContext: ModelPricing.Rates.LongContext(
                        thresholdInputTokens: 272_000,
                        input: 20,
                        output: 30,
                        cacheWrite5m: 20,
                        cacheWrite1h: 20,
                        cacheRead: 2
                    )
                ),
            ],
            defaultRate: TestPricing.table.defaultRate
        )
        let usage = TokenUsage(inputTokens: 100, outputTokens: 200, cacheReadTokens: 1_000,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)

        #expect(abs(pricing.cost(model: "model-long", usage: usage, contextInputTokens: 272_000) - 0.006) < 1e-9)
        #expect(abs(pricing.cost(model: "model-long", usage: usage, contextInputTokens: 272_001) - 0.010) < 1e-9)
    }

    @Test("Merged model usage preserves precomputed request-sensitive cost")
    func mergedUsagePreservesCost() {
        let entries = [
            ModelUsage(model: "model-a", messageCount: 1, usage: TokenUsage(inputTokens: 1), estimatedCost: 3),
            ModelUsage(model: "model-a", messageCount: 1, usage: TokenUsage(inputTokens: 2), estimatedCost: 5),
        ]

        let merged = entries.merged(pricing: TestPricing.table)
        let model = merged.first
        #expect(model?.usage.inputTokens == 3)
        #expect(model?.estimatedCost == 8)
    }

    @Test("User pricing files without long context remain compatible")
    func legacyPricingJSONCompatibility() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pricing.json")
        try TempDir.write("""
        {
          "models": {
            "legacy-model": {
              "input": 4.0,
              "output": 8.0,
              "cacheWrite5m": 4.0,
              "cacheWrite1h": 4.0,
              "cacheRead": 0.4
            }
          }
        }
        """, to: url)

        let pricing = ModelPricing.loadDefault(bundle: .main, userFile: url)
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0,
                               cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
        #expect(pricing.rate(for: "legacy-model").longContext == nil)
        #expect(abs(pricing.cost(model: "legacy-model", usage: usage, contextInputTokens: 1_000_000) - 4) < 1e-9)
    }

    @Test("The bundled default-pricing.json is present and parses")
    func bundledDefaultsLoad() {
        // In a host-app-backed test bundle, `.main` is the host app bundle,
        // which is where `default-pricing.json` is copied.
        let pricing = ModelPricing.loadDefault(bundle: .main, userFile: nil)
        #expect(pricing.hasExactRate(for: "claude-opus-4-7"))
        #expect(pricing.rate(for: "claude-opus-4-7").output == 75)
        #expect(pricing.hasExactRate(for: "gpt-5.4"))
        #expect(pricing.rate(for: "gpt-5.4").input == 2.5)
        #expect(pricing.rate(for: "gpt-5.4").cacheRead == 0.25)
        #expect(pricing.rate(for: "gpt-5.4").longContext?.output == 22.5)
        #expect(pricing.hasExactRate(for: "gpt-5.5"))
        #expect(pricing.rate(for: "gpt-5.5").output == 30)
        #expect(pricing.hasExactRate(for: "gpt-5.3-codex"))
        #expect(pricing.rate(for: "gpt-5.3-codex").cacheRead == 0.175)
        #expect(pricing.defaultRate.input == 3)
    }
}
