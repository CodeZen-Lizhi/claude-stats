import Foundation
import Observation

@MainActor
@Observable
final class UsageLimitStore {
    private(set) var reports: [ProviderKind: UsageLimitReport] = [:]
    private(set) var loadingProviders: Set<ProviderKind> = []
    private(set) var actionMessages: [ProviderKind: String] = [:]

    @ObservationIgnored private let registry: ProviderRegistry

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    func report(for provider: ProviderKind) -> UsageLimitReport? {
        reports[provider]
    }

    func isLoading(_ provider: ProviderKind) -> Bool {
        loadingProviders.contains(provider)
    }

    func actionMessage(for provider: ProviderKind) -> String? {
        actionMessages[provider]
    }

    func refresh(provider: ProviderKind, force: Bool = false, now: Date = .now) async {
        guard provider.supportsUsageLimits else { return }
        guard force || reports[provider] == nil else { return }
        guard !loadingProviders.contains(provider) else { return }
        loadingProviders.insert(provider)
        defer { loadingProviders.remove(provider) }

        guard let source = registry.provider(for: provider) else {
            reports[provider] = .unsupported(provider: provider)
            return
        }
        reports[provider] = await source.usageLimitReport(now: now)
    }

    func refreshSupportedProviders(force: Bool = false, now: Date = .now) async {
        for provider in ProviderKind.allCases where provider.supportsUsageLimits {
            await refresh(provider: provider, force: force, now: now)
        }
    }

    func recordActionMessage(_ message: String, for provider: ProviderKind) {
        actionMessages[provider] = message
    }
}
