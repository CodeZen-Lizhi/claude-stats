import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git diff render layout")
struct GitDiffRenderLayoutTests {
    @Test("Connector envelope touches the pane edges")
    func connectorEnvelopeTouchesPaneEdges() throws {
        let layout = fluidLayout("""
        @@ -1,1 +1,3 @@
        -old
        +new one
        +new two
        +new three
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let block = try #require(segment.blockRange.map { layout.blocks[$0] }.first)
        let columns = testColumns
        let projected = GitDiffFluidProjector(metrics: layout.metrics).projectedBlock(
            block,
            in: segment,
            virtualScrollY: segment.virtualStart + 8,
            visibleMinY: 0,
            columns: columns
        )
        let envelope = projected.connectorEnvelope(columns: columns)

        #expect(close(projected.oldRect.maxX, columns.leftPane.maxX))
        #expect(close(projected.newRect.minX, columns.rightPane.minX))
        #expect(close(envelope.leftX, columns.leftPane.maxX - 1))
        #expect(close(envelope.rightX, columns.rightPane.minX + 1))
    }

    @Test("Modified rows and connectors share the same fill color")
    func modifiedColorIsShared() {
        let palette = GitDiffRenderPalette.standard
        #expect(sameColor(palette.blockFill(for: .modification), palette.connectorFill(for: .modification)))
    }

    @Test("Diff kind fills use the shared requested palette")
    func diffKindFillsUseRequestedPalette() {
        let palette = GitDiffRenderPalette.standard
        #expect(sameColor(palette.blockFill(for: .modification), hexColor(0xF2FAFF)))
        #expect(sameColor(palette.blockFill(for: .deletion), hexColor(0xFFF0EF)))
        #expect(sameColor(palette.blockFill(for: .addition), hexColor(0xF7FFF5)))
        #expect(sameColor(palette.rowFill(for: .deletion), palette.blockFill(for: .deletion)))
        #expect(sameColor(palette.rowFill(for: .addition), palette.blockFill(for: .addition)))
        #expect(sameColor(palette.blockFill(for: .modification, state: .selected), hexColor(0xE6F4FF)))
        #expect(sameColor(palette.blockFill(for: .deletion, state: .selected), hexColor(0xFFDFDE)))
        #expect(sameColor(palette.blockFill(for: .addition, state: .selected), hexColor(0xEEFFEA)))
    }

    @Test("Selected fills sit between normal fills and hover strokes")
    func selectedFillsSitBetweenNormalAndStroke() {
        let palette = GitDiffRenderPalette.standard
        for kind in [GitDiffVisualKind.modification, .deletion, .addition] {
            let normal = luminance(palette.blockFill(for: kind))
            let selected = luminance(palette.blockFill(for: kind, state: .selected))
            let stroke = luminance(palette.blockStroke(for: kind))

            #expect(selected < normal)
            #expect(stroke < selected)
        }
    }

    @Test("Overview lane spacing is fixed to six points")
    func overviewLaneSpacingIsFixedToSixPoints() {
        let metrics = GitDiffRenderMetrics.standard
        for width in [CGFloat(320), CGFloat(260)] {
            let columns = GitDiffRenderLayout.columns(
                in: CGRect(x: 0, y: 0, width: width, height: 200),
                metrics: metrics
            )

            #expect(close(columns.overviewLane.minX - columns.rightPane.maxX, 6))
            #expect(close(width - columns.overviewLane.maxX, 6))
        }
    }

    @Test("Insertion anchors use the fixed anchor height")
    func insertionAnchorHeight() throws {
        let layout = fluidLayout("""
        @@ -1,1 +1,3 @@
         kept
        +new one
        +new two
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let block = try #require(segment.blockRange.map { layout.blocks[$0] }.first)

        #expect(block.visualKind == .addition)
        #expect(block.oldIsAnchor)
        #expect(!block.newIsAnchor)
        #expect(close(block.oldContentRect.height, layout.metrics.anchorHeight))
    }

    @Test("Deletion anchors use the fixed anchor height")
    func deletionAnchorHeight() throws {
        let layout = fluidLayout("""
        @@ -1,3 +1,1 @@
         kept
        -old one
        -old two
        """)
        let segment = try #require(layout.segments.first { $0.kind == .change })
        let block = try #require(segment.blockRange.map { layout.blocks[$0] }.first)

        #expect(block.visualKind == .deletion)
        #expect(!block.oldIsAnchor)
        #expect(block.newIsAnchor)
        #expect(close(block.newContentRect.height, layout.metrics.anchorHeight))
    }

    @Test("Hunk headers default to one line height")
    func hunkHeadersDefaultToOneLineHeight() throws {
        let layout = fluidLayout("""
        @@ -1,1 +1,1 @@
        -old
        +new
        """)
        let header = try #require(layout.segments.first { $0.kind == .hunkHeader })

        #expect(close(header.virtualHeight, layout.metrics.lineHeight))
        #expect(close(header.oldHeight, layout.metrics.lineHeight))
        #expect(close(header.newHeight, layout.metrics.lineHeight))
    }

    @Test("Expanded hunk headers use the compact detail height")
    func expandedHunkHeadersUseCompactDetailHeight() throws {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        let layout = GitDiffRenderLayout.build(
            from: StructuredFileDiff.build(from: fileDiff("""
            @@ -1,1 +1,1 @@
            -old
            +new
            """)),
            mode: .fluid,
            metrics: metrics,
            hunkHeaderExpansion: [GitDiffRenderLayout.hunkHeaderID(forHunkIndex: 0): 1]
        )
        let header = try #require(layout.segments.first { $0.kind == .hunkHeader })

        #expect(close(header.virtualHeight, metrics.lineHeight))
        #expect(close(header.oldHeight, metrics.lineHeight))
        #expect(close(header.newHeight, metrics.lineHeight))
    }

    @Test("Split change blocks are flush with the left window edge")
    func splitChangeBlocksAreFlushWithWindowEdge() {
        let layout = fluidLayout("""
        @@ -1,1 +1,1 @@
        -old
        +new
        """)
        let columns = layout.columns(in: CGRect(x: 0, y: 0, width: 320, height: 200))

        #expect(close(columns.leftPane.minX, 0))
        #expect(columns.rightPane.maxX < columns.overviewLane.minX)
    }

    @Test("Text measurement wraps long lines and long tokens")
    func textMeasurementWrapsLongContent() {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        let measurement = GitDiffTextMeasurement(font: GitDiffTextMeasurement.standardCodeFont(), metrics: metrics)

        #expect(close(measurement.height(for: "let short = true", width: 400), metrics.lineHeight))
        #expect(measurement.height(for: "let value = \(String(repeating: "wrapped ", count: 12))", width: 42) > metrics.lineHeight)
        #expect(measurement.height(for: String(repeating: "x", count: 80), width: 42) > metrics.lineHeight)
    }

    @Test("Blocks mode uses equal wrapped row height for paired lines")
    func blocksModeUsesEqualWrappedRowHeight() throws {
        let layout = narrowLayout("""
        @@ -1,1 +1,1 @@
        -let value = short
        +let value = \(String(repeating: "veryLongName", count: 8))
        """, mode: .blocks)
        let block = try #require(layout.blocks.first)
        let oldLine = try #require(layout.oldLines.first { $0.kind == .deletion })
        let newLine = try #require(layout.newLines.first { $0.kind == .addition })

        #expect(newLine.height > layout.metrics.lineHeight)
        #expect(close(oldLine.height, newLine.height))
        #expect(close(block.oldContentRect.height, newLine.height))
        #expect(close(block.newContentRect.height, newLine.height))
    }

    @Test("Fluid mode uses wrapped side heights in segment projection")
    func fluidModeUsesWrappedSideHeights() throws {
        let layout = narrowLayout("""
        @@ -1,1 +1,1 @@
        -let value = short
        +let value = \(String(repeating: "veryLongName", count: 8))
        """, mode: .fluid)
        let segment = try #require(layout.segments.first { $0.kind == .change })

        #expect(close(segment.oldHeight, layout.metrics.lineHeight))
        #expect(segment.newHeight > segment.oldHeight)
        #expect(close(segment.virtualHeight, segment.newHeight))
    }

    @Test("Coarse granularity keeps a mixed change in one modification block")
    func coarseGranularityKeepsMixedChangeTogether() {
        let layout = layout(for: mixedStructuredDiff(), mode: .fluid, granularity: .coarse)
        let changeSegments = layout.segments.filter { $0.kind == .change }

        #expect(changeSegments.count == 1)
        #expect(layout.blocks.map(\.visualKind) == [.modification])
    }

    @Test("Fine granularity splits mixed changes into ordered visual bands")
    func fineGranularitySplitsMixedChanges() {
        let layout = layout(for: mixedStructuredDiff(), mode: .fluid, granularity: .fine)
        let changeSegments = layout.segments.filter { $0.kind == .change }

        #expect(changeSegments.map(\.visualKind) == [.modification, .deletion, .addition, .modification])
        #expect(layout.blocks.map(\.visualKind) == [.modification, .deletion, .addition, .modification])
    }

    @Test("Fluid fine granularity anchors missing sides inside mixed changes")
    func fluidFineGranularityAnchorsMixedInsertionsAndDeletions() throws {
        let layout = layout(for: mixedStructuredDiff(), mode: .fluid, granularity: .fine)
        let deletion = try #require(layout.blocks.first { $0.visualKind == .deletion })
        let addition = try #require(layout.blocks.first { $0.visualKind == .addition })
        let deletionSegment = layout.segments[deletion.segmentIndex]
        let additionSegment = layout.segments[addition.segmentIndex]

        #expect(!deletion.oldIsAnchor)
        #expect(deletion.newIsAnchor)
        #expect(close(deletion.newContentRect.height, layout.metrics.lineHeight))
        #expect(close(deletionSegment.oldHeight, layout.metrics.lineHeight))
        #expect(close(deletionSegment.newHeight, 0))
        #expect(addition.oldIsAnchor)
        #expect(!addition.newIsAnchor)
        #expect(close(addition.oldContentRect.height, layout.metrics.lineHeight))
        #expect(close(additionSegment.oldHeight, 0))
        #expect(close(additionSegment.newHeight, layout.metrics.lineHeight))
    }

    @Test("Blocks fine granularity reserves equal placeholder height")
    func blocksFineGranularityUsesEqualPlaceholderHeight() throws {
        let layout = layout(for: mixedStructuredDiff(), mode: .blocks, granularity: .fine)
        let deletion = try #require(layout.blocks.first { $0.visualKind == .deletion })
        let addition = try #require(layout.blocks.first { $0.visualKind == .addition })

        #expect(!deletion.oldIsAnchor)
        #expect(!deletion.newIsAnchor)
        #expect(!addition.oldIsAnchor)
        #expect(!addition.newIsAnchor)
        #expect(close(deletion.oldContentRect.height, layout.metrics.lineHeight))
        #expect(close(deletion.newContentRect.height, layout.metrics.lineHeight))
        #expect(close(addition.oldContentRect.height, layout.metrics.lineHeight))
        #expect(close(addition.newContentRect.height, layout.metrics.lineHeight))
    }

    private var testColumns: GitDiffRenderColumns {
        GitDiffRenderColumns(
            leftPane: CGRect(x: 0, y: 0, width: 120, height: 300),
            gutter: CGRect(x: 120, y: 0, width: 80, height: 300),
            rightPane: CGRect(x: 200, y: 0, width: 120, height: 300),
            overviewLane: CGRect(x: 328, y: 0, width: 28, height: 300)
        )
    }

    private func fluidLayout(_ patch: String) -> GitDiffRenderLayout {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        return GitDiffRenderLayout.build(
            from: StructuredFileDiff.build(from: fileDiff(patch)),
            mode: .fluid,
            metrics: metrics
        )
    }

    private func layout(
        for diff: StructuredFileDiff,
        mode: DiffViewMode,
        granularity: GitDiffBlockGranularity,
        containerWidth: CGFloat = 1200
    ) -> GitDiffRenderLayout {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        return GitDiffRenderLayout.build(
            from: diff,
            mode: mode,
            metrics: metrics,
            granularity: granularity,
            containerWidth: containerWidth
        )
    }

    private func narrowLayout(_ patch: String, mode: DiffViewMode) -> GitDiffRenderLayout {
        var metrics = GitDiffRenderMetrics.standard
        metrics.lineHeight = 10
        return GitDiffRenderLayout.build(
            from: StructuredFileDiff.build(from: fileDiff(patch)),
            mode: mode,
            metrics: metrics,
            granularity: .coarse,
            containerWidth: 500
        )
    }

    private func mixedStructuredDiff() -> StructuredFileDiff {
        let oldModifiedOne = textLine(id: "old-mod-1", side: .old, kind: .deletion, text: "let name = old", oldLine: 1, newLine: nil)
        let newModifiedOne = textLine(id: "new-mod-1", side: .new, kind: .addition, text: "let name = new", oldLine: nil, newLine: 1)
        let deleted = textLine(id: "deleted", side: .old, kind: .deletion, text: "deleteOnly()", oldLine: 2, newLine: nil)
        let inserted = textLine(id: "inserted", side: .new, kind: .addition, text: "insertOnly()", oldLine: nil, newLine: 2)
        let oldModifiedTwo = textLine(id: "old-mod-2", side: .old, kind: .deletion, text: "return old", oldLine: 3, newLine: nil)
        let newModifiedTwo = textLine(id: "new-mod-2", side: .new, kind: .addition, text: "return new", oldLine: nil, newLine: 3)
        let pairs = [
            DiffLinePair(id: "pair-0", kind: .modified, oldLine: oldModifiedOne, newLine: newModifiedOne),
            DiffLinePair(id: "pair-1", kind: .deleted, oldLine: deleted, newLine: nil),
            DiffLinePair(id: "pair-2", kind: .inserted, oldLine: nil, newLine: inserted),
            DiffLinePair(id: "pair-3", kind: .modified, oldLine: oldModifiedTwo, newLine: newModifiedTwo)
        ]
        let block = ChangeBlock(
            id: "mixed-change",
            oldLines: [oldModifiedOne, deleted, oldModifiedTwo],
            newLines: [newModifiedOne, inserted, newModifiedTwo],
            linePairs: pairs
        )
        return StructuredFileDiff(
            path: "A.swift",
            isBinary: false,
            fileHeaders: [],
            hunks: [
                DiffHunk(
                    id: "hunk-0",
                    header: "@@ -1,3 +1,3 @@",
                    oldStart: 1,
                    newStart: 1,
                    segments: [.change(id: "segment-0", block: block)]
                )
            ],
            unifiedLines: []
        )
    }

    private func textLine(
        id: String,
        side: DiffTextLine.Side,
        kind: DiffLine.Kind,
        text: String,
        oldLine: Int?,
        newLine: Int?
    ) -> DiffTextLine {
        DiffTextLine(
            id: id,
            side: side,
            kind: kind,
            text: text,
            oldLine: oldLine,
            newLine: newLine,
            inlineSpans: []
        )
    }

    private func fileDiff(_ patch: String) -> FileDiff {
        FileDiff(path: "A.swift", isBinary: false, lines: GitAnalyzer.parseUnifiedDiff(patch))
    }

    private func close(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func sameColor(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.0001) -> Bool {
        guard let left = lhs.usingColorSpace(.deviceRGB), let right = rhs.usingColorSpace(.deviceRGB) else {
            return lhs.isEqual(rhs)
        }
        return close(left.redComponent, right.redComponent, tolerance: tolerance)
            && close(left.greenComponent, right.greenComponent, tolerance: tolerance)
            && close(left.blueComponent, right.blueComponent, tolerance: tolerance)
            && close(left.alphaComponent, right.alphaComponent, tolerance: tolerance)
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
        return rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114
    }

    private func hexColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
