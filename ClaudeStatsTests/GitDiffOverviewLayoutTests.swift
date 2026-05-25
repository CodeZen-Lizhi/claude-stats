import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git diff overview layout")
struct GitDiffOverviewLayoutTests {
    @Test("Split overview entries use block visual kinds")
    func splitOverviewEntriesUseBlockKinds() throws {
        let modification = try firstOverviewEntry(for: """
        @@ -1,1 +1,1 @@
        -let value = oldName
        +let value = newName
        """, mode: .fluid)
        let addition = try firstOverviewEntry(for: """
        @@ -1,1 +1,2 @@
         kept
        +new
        """, mode: .fluid)
        let deletion = try firstOverviewEntry(for: """
        @@ -1,2 +1,1 @@
         kept
        -old
        """, mode: .fluid)

        #expect(modification.visualKind == .modification)
        #expect(addition.visualKind == .addition)
        #expect(deletion.visualKind == .deletion)
    }

    @Test("Overview entries are scaled into the lane with a readable minimum height")
    func overviewEntriesScaleIntoLane() throws {
        let layout = renderLayout("""
        @@ -1,1 +1,1 @@
        -old
        +new
        """, mode: .fluid)
        let lane = CGRect(x: 0, y: 0, width: 14, height: 80)
        let overview = GitDiffOverviewLayout.build(from: layout, in: lane, minEntryHeight: 3)
        let entry = try #require(overview.entries.first)

        #expect(entry.rect.minY >= lane.minY)
        #expect(entry.rect.maxY <= lane.maxY)
        #expect(entry.rect.height >= 3)
    }

    @Test("Unified overview merges consecutive same-kind rows")
    func unifiedOverviewMergesConsecutiveRows() {
        let layout = renderLayout("""
        @@ -1,1 +1,3 @@
         kept
        +new one
        +new two
        """, mode: .unified)
        let overview = GitDiffOverviewLayout.build(from: layout, in: CGRect(x: 0, y: 0, width: 14, height: 80))

        #expect(overview.entries.map(\.visualKind) == [.addition])
    }

    private func firstOverviewEntry(for patch: String, mode: DiffViewMode) throws -> GitDiffOverviewEntry {
        let overview = GitDiffOverviewLayout.build(
            from: renderLayout(patch, mode: mode),
            in: CGRect(x: 0, y: 0, width: 14, height: 80)
        )
        return try #require(overview.entries.first)
    }

    private func renderLayout(_ patch: String, mode: DiffViewMode) -> GitDiffRenderLayout {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        return GitDiffRenderLayout.build(
            from: StructuredFileDiff.build(from: fileDiff(patch)),
            mode: mode,
            metrics: metrics,
            containerWidth: 360
        )
    }

    private func fileDiff(_ patch: String) -> FileDiff {
        FileDiff(path: "A.swift", isBinary: false, lines: GitAnalyzer.parseUnifiedDiff(patch))
    }
}
