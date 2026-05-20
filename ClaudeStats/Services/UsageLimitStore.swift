import Foundation
import Observation

@MainActor
@Observable
final class UsageLimitStore {
    private(set) var reports: [ProviderKind: UsageLimitReport] = [:]
    private(set) var loadingProviders: Set<ProviderKind> = []
    private(set) var actionMessages: [ProviderKind: String] = [:]
    private(set) var claudeDesktopPermissionIssue: ClaudeDesktopUsagePermissionIssue?
    private(set) var claudeDesktopAccessibilityRecheckPending = false

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling
    @ObservationIgnored private let claudeDesktopCaptureService: any ClaudeDesktopUsageCapturing
    @ObservationIgnored private let claudeDesktopAccessibilityPermissionChecker: any ClaudeDesktopAccessibilityPermissionChecking

    init(
        registry: ProviderRegistry,
        claudeBridgeInstaller: any ClaudeUsageLimitBridgeInstalling = ClaudeUsageLimitBridgeInstaller(),
        claudeDesktopCaptureService: any ClaudeDesktopUsageCapturing = ClaudeDesktopUsageCaptureService(),
        claudeDesktopAccessibilityPermissionChecker: any ClaudeDesktopAccessibilityPermissionChecking = SystemClaudeDesktopAccessibilityPermissionChecker()
    ) {
        self.registry = registry
        self.claudeBridgeInstaller = claudeBridgeInstaller
        self.claudeDesktopCaptureService = claudeDesktopCaptureService
        self.claudeDesktopAccessibilityPermissionChecker = claudeDesktopAccessibilityPermissionChecker
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

    func captureClaudeDesktopUsage(trigger: ClaudeDesktopUsageCaptureTrigger) async {
        guard !loadingProviders.contains(.claude) else { return }
        loadingProviders.insert(.claude)
        let outcome = await claudeDesktopCaptureService.capture(trigger: trigger)
        loadingProviders.remove(.claude)

        switch outcome {
        case .captured:
            clearClaudeDesktopPermissionState()
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = "Claude Desktop usage captured."
            }
            await refresh(provider: .claude, force: true)
        case .skipped:
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = "Open Claude Desktop, then try reading usage again."
            }
        case .failed(let error):
            claudeDesktopPermissionIssue = error.permissionIssue
            if trigger.shouldShowUserMessage {
                actionMessages[.claude] = error.localizedDescription
            }
        }
    }

    func beginClaudeDesktopAccessibilityPermissionRecheck() {
        claudeDesktopAccessibilityRecheckPending = true
    }

    func runPendingClaudeDesktopAccessibilityPermissionRecheck(
        maxAttempts: Int = 8,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async {
        guard claudeDesktopAccessibilityRecheckPending else { return }

        for attempt in 0..<max(1, maxAttempts) {
            guard !Task.isCancelled else { return }
            if claudeDesktopAccessibilityPermissionChecker.isTrusted(prompt: false) {
                claudeDesktopAccessibilityRecheckPending = false
                clearClaudeDesktopPermissionState()
                await captureClaudeDesktopUsage(trigger: .permissionRecheck)
                return
            }

            guard attempt < maxAttempts - 1 else { break }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }

        ClaudeDesktopAccessibilityPermissionDiagnostics.logNotTrusted(context: "post-settings recheck")
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

    private func clearClaudeDesktopPermissionState() {
        claudeDesktopPermissionIssue = nil
        if isClaudeDesktopPermissionActionMessage(actionMessages[.claude]) {
            actionMessages[.claude] = nil
        }
    }

    private func isClaudeDesktopPermissionActionMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let permissionMessages = [
            ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired.localizedDescription,
            ClaudeDesktopUsageCaptureError.screenRecordingPermissionRequired.localizedDescription,
        ]
        return permissionMessages.contains(message)
    }
}
