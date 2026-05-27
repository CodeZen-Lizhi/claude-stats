import Foundation
import Testing
@testable import ClaudeStats

@Suite("Diagnostics exporter")
struct DiagnosticsExporterTests {
    @Test("Redaction removes home path and secrets")
    func redactionRemovesHomePathAndSecrets() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let text = """
        path=\(home)/.codex/sessions
        api_key=sk-1234567890abcdef
        jwt=eyJabc.def.ghi
        """

        let redacted = DiagnosticsExporter.redactText(text)

        #expect(!redacted.contains(home))
        #expect(!redacted.contains("sk-1234567890abcdef"))
        #expect(!redacted.contains("eyJabc.def.ghi"))
        #expect(redacted.contains("~/.codex/sessions"))
    }

    @MainActor
    @Test("Report contains support sections without transcript text")
    func reportContainsSupportSectionsWithoutTranscriptText() {
        let env = AppEnvironment.preview()
        let report = DiagnosticsExporter().makeReport(environment: env, now: Date(timeIntervalSince1970: 0))

        #expect(report.summary.appVersion.contains("("))
        #expect(report.preferences.selectedProvider == ProviderKind.codex.rawValue)
        #expect(report.scanner.visibleSessionCount > 0)
        #expect(!report.diagnosisText.contains("Wire up the websocket reconnect logic"))
    }
}
