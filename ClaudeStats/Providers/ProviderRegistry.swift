import Foundation

/// The Codex provider registry. The app remains provider-shaped internally, but
/// intentionally registers only OpenAI Codex.
struct ProviderRegistry: Sendable {
    let providers: [any Provider]

    init(pricing: ModelPricing,
         codexPaths: CodexPaths = .default) {
        providers = [
            CodexProvider(paths: codexPaths, pricing: pricing),
        ]
    }

    init(providers: [any Provider]) {
        self.providers = providers
    }

    func provider(for kind: ProviderKind) -> (any Provider)? {
        providers.first { $0.kind == kind }
    }
}
