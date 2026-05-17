import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git language statistics")
struct GitLanguageStatsTests {
    @Test("Linguist breakdown JSON parses language sizes and files")
    func linguistBreakdownParsing() throws {
        let report = try GitLinguistReport.parse("""
        {
          "Swift": {
            "size": 489600,
            "percentage": "88.60",
            "files": [
              "ClaudeStats/App/ClaudeStatsApp.swift",
              "ClaudeStats/Services/GitAnalyzer.swift"
            ]
          },
          "YAML": {
            "size": 24480,
            "percentage": "4.40",
            "files": ["project.yml"]
          }
        }
        """)

        #expect(report.languages.map(\.name) == ["Swift", "YAML"])
        #expect(report.totalBytes == 514_080)
        #expect(report.analyzedFileCount == 3)
        #expect(report.filePaths == [
            "ClaudeStats/App/ClaudeStatsApp.swift",
            "ClaudeStats/Services/GitAnalyzer.swift",
            "project.yml",
        ])
        #expect(report.languages.first?.percentage == 88.60)
    }

    @Test("scc JSON parses line metrics and per-file paths")
    func sccParsing() throws {
        let report = try GitSCCReport.parse("""
        [
          {
            "Name": "Swift",
            "Bytes": 489600,
            "Code": 14880,
            "Comment": 1140,
            "Blank": 1293,
            "Lines": 17313,
            "Count": 14,
            "Files": [
              { "Location": "ClaudeStats/App/ClaudeStatsApp.swift" },
              { "Location": "ClaudeStats/Services/GitAnalyzer.swift" }
            ]
          },
          {
            "Name": "Total",
            "Bytes": 489600,
            "Code": 14880,
            "Comment": 1140,
            "Blank": 1293,
            "Lines": 17313,
            "Count": 14
          }
        ]
        """)

        #expect(report.rows.count == 1)
        let swift = try #require(report.rows.first)
        #expect(swift.language == "Swift")
        #expect(swift.fileCount == 14)
        #expect(swift.sizeBytes == 489_600)
        #expect(swift.totalLines == 17_313)
        #expect(swift.sourceLines == 14_880)
        #expect(swift.filePaths == [
            "ClaudeStats/App/ClaudeStatsApp.swift",
            "ClaudeStats/Services/GitAnalyzer.swift",
        ])
        #expect(report.totalLines == 17_313)
        #expect(report.sourceLines == 14_880)
    }

    @Test("unavailable stats preserve scope and skipped file count")
    func unavailableStats() {
        let stats = GitRepoCodeStats.unavailable(
            scope: .workingTree,
            totalFiles: 42,
            warning: "missing runtime"
        )

        #expect(stats.engine == .unavailable)
        #expect(stats.scope == .workingTree)
        #expect(stats.totalFiles == 42)
        #expect(stats.skippedFiles == 42)
        #expect(stats.warning == "missing runtime")
        #expect(stats.languageRows.isEmpty)
    }
}
