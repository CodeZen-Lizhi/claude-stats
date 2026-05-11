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

    @Test("The bundled default-pricing.json is present and parses")
    func bundledDefaultsLoad() {
        // In a host-app-backed test bundle, `.main` is the host app bundle,
        // which is where `default-pricing.json` is copied.
        let pricing = ModelPricing.loadDefault(bundle: .main, userFile: nil)
        #expect(pricing.hasExactRate(for: "claude-opus-4-7"))
        #expect(pricing.rate(for: "claude-opus-4-7").output == 75)
        #expect(pricing.defaultRate.input == 3)
    }
}
