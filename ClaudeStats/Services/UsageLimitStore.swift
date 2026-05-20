import Foundation
import Observation

@MainActor
@Observable
final class UsageLimitStore {
    private(set) var reports: [ProviderKind: UsageLimitReport] = [:]
    private(set) var loadingProviders: Set<ProviderKind> = []
    private(set) var actionMessages: [ProviderKind: String] = [:]

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling

    init(
        registry: ProviderRegistry,
        claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling = ClaudeUsageLimitBridgeInstaller()
    ) {
        self.registry = registry
        self.claudeBridgeInstaller = claudeBridgeInstaller
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

    func installClaudeBridge() {
        do {
            let configuration = try claudeBridgeInstaller.install()
            actionMessages[.claude] = "Bridge installed. Paste the settings snippet into \(configuration.settingsURL.path)."
        } catch {
            actionMessages[.claude] = "Could not install bridge: \(error.localizedDescription)"
        }
    }

    func claudeSettingsSnippet() -> String {
        claudeBridgeInstaller.settingsSnippet()
    }

    func claudeSettingsURL() -> URL {
        claudeBridgeInstaller.settingsURL
    }

    func recordActionMessage(_ message: String, for provider: ProviderKind) {
        actionMessages[provider] = message
    }
}
