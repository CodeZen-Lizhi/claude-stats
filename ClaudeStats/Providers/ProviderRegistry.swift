import Foundation

/// The set of providers the app reads from. Built once, with the shared
/// ``ModelPricing`` table threaded in so providers can attach cost figures.
///
/// Adding a provider = a new folder under `Providers/`, a `Provider`
/// conformer, and one line in ``init(pricing:)``.
struct ProviderRegistry: Sendable {
    let providers: [any Provider]

    init(pricing: ModelPricing, paths: ClaudePaths = .default) {
        providers = [
            ClaudeProvider(paths: paths, pricing: pricing),
        ]
    }

    func provider(for kind: ProviderKind) -> (any Provider)? {
        providers.first { $0.kind == kind }
    }
}
