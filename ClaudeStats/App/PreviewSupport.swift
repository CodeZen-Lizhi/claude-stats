#if DEBUG
import Foundation

// Sample data + factory used by the `#Preview` blocks throughout the app.
// Compiled out of release builds.

extension AppEnvironment {
    /// An environment wired with canned data (or empty), with preferences
    /// stored in a throwaway suite so previews don't touch real defaults.
    static func preview(populated: Bool = true) -> AppEnvironment {
        let pricing = ModelPricing.fallback
        let store = SessionStore(registry: ProviderRegistry(pricing: pricing), pricing: pricing)
        store.loadPreviewSessions(populated ? Session.previewSamples(pricing: pricing) : [])
        // Fresh, throwaway defaults so previews always reflect the code defaults.
        let suiteName = "com.claudestats.preview"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppEnvironment(pricing: pricing, preferences: Preferences(defaults: defaults), store: store)
    }
}

extension Session {
    static func previewSamples(pricing: ModelPricing = .fallback) -> [Session] {
        func usage(_ i: Int, _ o: Int, _ cr: Int, _ c5: Int = 0) -> TokenUsage {
            TokenUsage(inputTokens: i, outputTokens: o, cacheReadTokens: cr,
                       cacheCreation5mTokens: c5, cacheCreation1hTokens: 0)
        }
        func model(_ name: String, _ count: Int, _ u: TokenUsage) -> ModelUsage {
            ModelUsage(model: name, messageCount: count, usage: u, pricing: pricing)
        }
        let now = Date.now
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now) ?? now }
        func dayStart(_ n: Int) -> Date { cal.startOfDay(for: daysAgo(n)) }
        /// `(daysAgo, hour, model, usage)` → an hourly ``ModelBucket``.
        func bucket(_ d: Int, _ h: Int, _ name: String, _ u: TokenUsage) -> ModelBucket {
            let start = cal.date(byAdding: .hour, value: h, to: dayStart(d)) ?? dayStart(d)
            return ModelBucket(model: name, start: start, usage: u)
        }

        return [
            Session(
                id: "-Users-dev-projects-aurora::a1", externalID: "a1", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-aurora",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-aurora/a1.jsonl",
                cwd: "/Users/dev/projects/aurora", lastModified: daysAgo(0), fileSize: 412_000,
                stats: SessionStats(
                    title: "Wire up the websocket reconnect logic",
                    messageCount: 84, firstActivity: daysAgo(1), lastActivity: daysAgo(0),
                    models: [
                        model("claude-opus-4-7", 41, usage(120_000, 38_000, 1_400_000, 90_000)),
                        model("claude-haiku-4-5", 12, usage(8_000, 2_000, 50_000)),
                    ],
                    timeline: [
                        bucket(1, 14, "claude-opus-4-7", usage(20_000, 6_000, 240_000, 15_000)),
                        bucket(1, 15, "claude-opus-4-7", usage(28_000, 8_000, 300_000, 18_000)),
                        bucket(1, 16, "claude-opus-4-7", usage(12_000, 4_000, 160_000, 12_000)),
                        bucket(1, 15, "claude-haiku-4-5", usage(3_000, 800, 18_000)),
                        bucket(0, 9, "claude-opus-4-7", usage(18_000, 6_000, 200_000, 12_000)),
                        bucket(0, 10, "claude-opus-4-7", usage(30_000, 10_000, 320_000, 20_000)),
                        bucket(0, 11, "claude-opus-4-7", usage(20_000, 6_000, 230_000, 13_000)),
                        bucket(0, 9, "claude-haiku-4-5", usage(2_000, 600, 14_000)),
                        bucket(0, 11, "claude-haiku-4-5", usage(3_000, 600, 18_000)),
                    ]
                )
            ),
            Session(
                id: "-Users-dev-projects-ledger::b2", externalID: "b2", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-ledger",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-ledger/b2.jsonl",
                cwd: "/Users/dev/projects/ledger", lastModified: daysAgo(2), fileSize: 96_000,
                stats: SessionStats(
                    title: "Fix the off-by-one in pagination",
                    messageCount: 22, firstActivity: daysAgo(2), lastActivity: daysAgo(2),
                    models: [model("claude-sonnet-4-6", 11, usage(34_000, 9_500, 210_000, 12_000))],
                    timeline: [
                        bucket(2, 13, "claude-sonnet-4-6", usage(16_000, 4_500, 100_000, 6_000)),
                        bucket(2, 14, "claude-sonnet-4-6", usage(18_000, 5_000, 110_000, 6_000)),
                    ]
                )
            ),
            Session(
                id: "-Users-dev-projects-aurora::c3", externalID: "c3", provider: .claude,
                projectDirectoryName: "-Users-dev-projects-aurora",
                filePath: "/Users/dev/.claude/projects/-Users-dev-projects-aurora/c3.jsonl",
                cwd: "/Users/dev/projects/aurora", lastModified: daysAgo(9), fileSize: 250_000,
                stats: SessionStats(
                    title: "Migrate the settings screen to the new design",
                    messageCount: 53, firstActivity: daysAgo(10), lastActivity: daysAgo(9),
                    models: [
                        model("claude-opus-4-7", 26, usage(70_000, 24_000, 880_000, 50_000)),
                        model("claude-sonnet-4-6", 9, usage(12_000, 3_000, 60_000, 4_000)),
                    ],
                    timeline: [
                        bucket(10, 17, "claude-opus-4-7", usage(30_000, 10_000, 380_000, 20_000)),
                        bucket(10, 18, "claude-sonnet-4-6", usage(12_000, 3_000, 60_000, 4_000)),
                        bucket(9, 10, "claude-opus-4-7", usage(40_000, 14_000, 500_000, 30_000)),
                    ]
                )
            ),
            Session(
                id: "codex::d4", externalID: "d4", provider: .codex,
                projectDirectoryName: "/Users/dev/projects/tag",
                filePath: "/Users/dev/.codex/sessions/2026/01/01/rollout-2026-01-01T10-00-00-d4.jsonl",
                cwd: "/Users/dev/projects/tag", lastModified: daysAgo(1), fileSize: 180_000,
                stats: SessionStats(
                    title: "Tidy up the markdown renderer",
                    messageCount: 31, firstActivity: daysAgo(1), lastActivity: daysAgo(1),
                    models: [model("gpt-5.1-codex", 14, usage(40_000, 6_000, 120_000))],
                    timeline: [
                        bucket(1, 11, "gpt-5.1-codex", usage(22_000, 3_000, 70_000)),
                        bucket(1, 12, "gpt-5.1-codex", usage(18_000, 3_000, 50_000)),
                    ]
                )
            ),
        ]
    }

    static var previewSamples: [Session] { previewSamples() }
}
#endif
