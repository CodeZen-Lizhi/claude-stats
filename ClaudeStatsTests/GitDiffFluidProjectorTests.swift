import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git diff fluid projector")
struct GitDiffFluidProjectorTests {
    @Test("One old line to three new lines advances the new side faster")
    func oneToThreeSlope() throws {
        let layout = fluidLayout("""
        @@ -1,1 +1,3 @@
        -old
        +new one
        +new two
        +new three
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let virtualY = segment.virtualStart + 9

        #expect(close(projector.sideOffset(for: segment, side: .old, virtualScrollY: virtualY), 3))
        #expect(close(projector.sideOffset(for: segment, side: .new, virtualScrollY: virtualY), 9))
    }

    @Test("Three old lines to one new line advances the old side faster")
    func threeToOneSlope() throws {
        let layout = fluidLayout("""
        @@ -1,3 +1,1 @@
        -old one
        -old two
        -old three
        +new
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let virtualY = segment.virtualStart + 9

        #expect(close(projector.sideOffset(for: segment, side: .old, virtualScrollY: virtualY), 9))
        #expect(close(projector.sideOffset(for: segment, side: .new, virtualScrollY: virtualY), 3))
    }

    @Test("Pure insertion keeps the old side anchored")
    func pureInsertionPinsOldAnchor() throws {
        let layout = fluidLayout("""
        @@ -1,1 +1,3 @@
         kept
        +new one
        +new two
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let block = try #require(segment.blockRange.map { layout.blocks[$0] }.first)
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let columns = testColumns

        let first = projector.screenRect(for: block.oldContentRect, side: .old, in: segment, virtualScrollY: segment.virtualStart + 2, columns: columns)
        let second = projector.screenRect(for: block.oldContentRect, side: .old, in: segment, virtualScrollY: segment.virtualStart + 12, columns: columns)

        #expect(block.oldIsAnchor)
        #expect(close(first.minY, second.minY))
        #expect(close(block.oldContentRect.height, layout.metrics.lineHeight))
    }

    @Test("Pure deletion keeps the new side anchored")
    func pureDeletionPinsNewAnchor() throws {
        let layout = fluidLayout("""
        @@ -1,3 +1,1 @@
         kept
        -old one
        -old two
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let block = try #require(segment.blockRange.map { layout.blocks[$0] }.first)
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let columns = testColumns

        let first = projector.screenRect(for: block.newContentRect, side: .new, in: segment, virtualScrollY: segment.virtualStart + 2, columns: columns)
        let second = projector.screenRect(for: block.newContentRect, side: .new, in: segment, virtualScrollY: segment.virtualStart + 12, columns: columns)

        #expect(block.newIsAnchor)
        #expect(close(first.minY, second.minY))
        #expect(close(block.newContentRect.height, layout.metrics.lineHeight))
    }

    @Test("Offsets are monotonic across segment boundaries")
    func offsetsAreMonotonic() throws {
        let layout = fluidLayout("""
        @@ -1,2 +1,4 @@
         kept
        -old
        +new one
        +new two
        +new three
        """)
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        var previousOld: CGFloat = 0
        var previousNew: CGFloat = 0

        for segment in layout.segments {
            for y in stride(from: segment.virtualStart, through: segment.virtualEnd, by: 2.5) {
                let old = segment.oldContentY + projector.sideOffset(for: segment, side: .old, virtualScrollY: y)
                let new = segment.newContentY + projector.sideOffset(for: segment, side: .new, virtualScrollY: y)
                #expect(old + 0.0001 >= previousOld)
                #expect(new + 0.0001 >= previousNew)
                previousOld = old
                previousNew = new
            }
        }
    }

    @Test("Fine granularity pins insertion bands inside mixed changes")
    func fineGranularityPinsMixedInsertionBand() throws {
        let layout = fluidLayout("""
        @@ -1,2 +1,3 @@
        -let value = oldName
        -deleteOnlyAlpha()
        +let value = newName
        +insertOnlyBeta()
        +insertOnlyGamma()
        """, granularity: .fine)
        let block = try #require(layout.blocks.first { $0.visualKind == .addition })
        let segment = layout.segments[block.segmentIndex]
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let columns = testColumns

        let first = projector.screenRect(for: block.oldContentRect, side: .old, in: segment, virtualScrollY: segment.virtualStart + 2, columns: columns)
        let second = projector.screenRect(for: block.oldContentRect, side: .old, in: segment, virtualScrollY: segment.virtualStart + 8, columns: columns)

        #expect(block.oldIsAnchor)
        #expect(close(segment.oldHeight, 0))
        #expect(segment.newHeight > 0)
        #expect(close(first.minY, second.minY))
    }

    @Test("Fine granularity pins deletion bands inside mixed changes")
    func fineGranularityPinsMixedDeletionBand() throws {
        let layout = fluidLayout("""
        @@ -1,3 +1,2 @@
        -let value = oldName
        -deleteOnlyAlpha()
        -deleteOnlyBeta()
        +let value = newName
        +insertOnlyGamma()
        """, granularity: .fine)
        let block = try #require(layout.blocks.first { $0.visualKind == .deletion })
        let segment = layout.segments[block.segmentIndex]
        let projector = GitDiffFluidProjector(metrics: layout.metrics)
        let columns = testColumns

        let first = projector.screenRect(for: block.newContentRect, side: .new, in: segment, virtualScrollY: segment.virtualStart + 2, columns: columns)
        let second = projector.screenRect(for: block.newContentRect, side: .new, in: segment, virtualScrollY: segment.virtualStart + 8, columns: columns)

        #expect(block.newIsAnchor)
        #expect(segment.oldHeight > 0)
        #expect(close(segment.newHeight, 0))
        #expect(close(first.minY, second.minY))
    }

    private var testColumns: GitDiffRenderColumns {
        GitDiffRenderColumns(
            leftPane: CGRect(x: 0, y: 0, width: 120, height: 300),
            gutter: CGRect(x: 120, y: 0, width: 80, height: 300),
            rightPane: CGRect(x: 200, y: 0, width: 120, height: 300)
        )
    }

    private func fluidLayout(
        _ patch: String,
        granularity: GitDiffBlockGranularity = .coarse
    ) -> GitDiffRenderLayout {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        return GitDiffRenderLayout.build(
            from: StructuredFileDiff.build(from: fileDiff(patch)),
            mode: .fluid,
            metrics: metrics,
            granularity: granularity
        )
    }

    private func fileDiff(_ patch: String) -> FileDiff {
        FileDiff(path: "A.swift", isBinary: false, lines: GitAnalyzer.parseUnifiedDiff(patch))
    }

    private func close(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
