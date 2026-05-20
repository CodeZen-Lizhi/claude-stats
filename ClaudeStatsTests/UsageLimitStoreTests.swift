import Foundation
import Testing
@testable import ClaudeStats

@Suite("Usage limit store")
struct UsageLimitStoreTests {
    @MainActor
    @Test("Refresh caches provider reports")
    func refreshCachesReports() async {
        let provider = FakeUsageLimitProvider(kind: .codex, report: Self.report(used: 10))
        let store = UsageLimitStore(registry: ProviderRegistry(providers: [provider]))

        await store.refresh(provider: .codex)
        #expect(store.report(for: .codex)?.snapshot?.windows.first?.usedPercent == 10)

        provider.report = Self.report(used: 20)
        await store.refresh(provider: .codex)

        #expect(store.report(for: .codex)?.snapshot?.windows.first?.usedPercent == 10)
        #expect(provider.callCount == 1)

        await store.refresh(provider: .codex, force: true)

        #expect(store.report(for: .codex)?.snapshot?.windows.first?.usedPercent == 20)
        #expect(provider.callCount == 2)
        #expect(store.isLoading(.codex) == false)
    }

    @MainActor
    @Test("Unsupported providers are ignored")
    func unsupportedProvidersAreIgnored() async {
        let store = UsageLimitStore(registry: ProviderRegistry(providers: []))

        await store.refresh(provider: .gemini, force: true)

        #expect(store.report(for: .gemini) == nil)
    }

    private static func report(used: Double) -> UsageLimitReport {
        .fresh(
            provider: .codex,
            snapshot: UsageLimitSnapshot(
                provider: .codex,
                windows: [UsageLimitWindow(id: "primary", label: "5h", usedPercent: used, resetAt: nil, windowMinutes: 300)],
                capturedAt: .now,
                sourceLabel: "test",
                sourcePath: nil,
                planType: nil,
                limitID: nil
            )
        )
    }
}

private final class FakeUsageLimitProvider: Provider, @unchecked Sendable {
    let kind: ProviderKind
    var dataDirectoryExists: Bool { true }
    var report: UsageLimitReport
    private(set) var callCount = 0

    init(kind: ProviderKind, report: UsageLimitReport) {
        self.kind = kind
        self.report = report
    }

    func discoverSessions() async -> [Session] { [] }
    func parse(_ session: Session) async -> SessionStats? { nil }

    func usageLimitReport(now: Date) async -> UsageLimitReport {
        callCount += 1
        return report
    }
}
