import Testing
@testable import ClaudeStats

@Suite("Beam avatar generator")
struct BeamAvatarTests {
    @Test("Same seed generates stable avatar data")
    func stableForSameSeed() {
        let first = BoringBeamAvatar.generate(name: "avatar-seed")
        let second = BoringBeamAvatar.generate(name: "avatar-seed")

        #expect(first == second)
    }

    @Test("Different seeds change at least one visible avatar parameter")
    func differentSeedsVaryAvatar() {
        let first = BoringBeamAvatar.generate(name: "avatar-seed-a")
        let second = BoringBeamAvatar.generate(name: "avatar-seed-b")

        #expect(first != second)
    }

    @Test("Contrast follows the original black or white YIQ threshold")
    func contrastUsesBlackOrWhite() {
        #expect(BoringBeamAvatar.contrast(for: "#FFFFFF") == "#000000")
        #expect(BoringBeamAvatar.contrast(for: "#000000") == "#FFFFFF")
        #expect(BoringBeamAvatar.contrast(for: "#F0AB3D") == "#000000")
        #expect(BoringBeamAvatar.contrast(for: "#146A7C") == "#FFFFFF")
    }
}
