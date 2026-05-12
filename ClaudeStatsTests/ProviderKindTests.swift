import Testing
@testable import ClaudeStats

@Suite("ProviderKind")
struct ProviderKindTests {

    @Test("Canonical order and full set")
    func allCases() {
        #expect(ProviderKind.allCases == [.claude, .codex, .antigravity, .kimi, .minimax])
    }

    @Test("Every case has a non-empty asset name, short name, and display name")
    func metadata() {
        for kind in ProviderKind.allCases {
            #expect(!kind.assetName.isEmpty)
            #expect(!kind.shortName.isEmpty)
            #expect(!kind.displayName.isEmpty)
        }
    }
}
