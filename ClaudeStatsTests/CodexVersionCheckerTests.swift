import Foundation
import Testing
@testable import ClaudeStats

@Suite("Codex Version Checker")
struct CodexVersionCheckerTests {
    @Test("PATH enrichment includes common GUI-missing install locations")
    func pathEnrichmentAddsCommonLocations() {
        let path = CodexLocalVersionResolver.enrichedPATH(
            environment: ["PATH": "/usr/bin:/opt/homebrew/bin"],
            homeDirectory: "/Users/test"
        )

        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/opt/homebrew/bin")
        #expect(parts.contains("/Users/test/.volta/bin"))
        #expect(parts.contains("/Users/test/.npm-global/bin"))
        #expect(parts.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(parts.contains("/usr/bin"))
    }

    @Test("Command candidates use enriched PATH before shell fallback")
    func commandCandidatesUseEnrichedPath() {
        let candidates = CodexLocalVersionResolver.commandCandidates(
            environment: ["PATH": "/usr/bin"],
            homeDirectory: "/Users/test"
        )

        #expect(candidates.first?.executablePath == "/usr/bin/env")
        #expect(candidates.first?.arguments == ["codex", "--version"])
        #expect(candidates.first?.environment["PATH"]?.contains("/opt/homebrew/bin") == true)
        #expect(candidates.map(\.executablePath).contains("/bin/zsh"))
    }

    @Test("Version extraction handles Codex CLI output")
    func versionExtractionHandlesCLIOutput() {
        #expect(CodexLocalVersionResolver.extractVersion(from: "codex-cli 0.133.0") == "0.133.0")
        #expect(CodexLocalVersionResolver.extractVersion(from: "codex 1.2.3-beta.1") == "1.2.3")
        #expect(CodexLocalVersionResolver.extractVersion(from: "unknown") == nil)
    }
}
