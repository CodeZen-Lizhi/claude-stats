import CoreGraphics
import Foundation

enum GitDiffRenderSide {
    case old
    case new
}

enum GitDiffVisualKind: Hashable {
    case addition
    case deletion
    case modification
    case context
    case hunkHeader
}

struct GitDiffRenderMetrics: Hashable {
    var lineHeight: CGFloat = 18
    var gutterWidth: CGFloat = 86
    var lineNumberWidth: CGFloat = 46
    var horizontalPadding: CGFloat = 0
    var textLeftPadding: CGFloat = 8
    var bottomPadding: CGFloat = 24

    var anchorHeight: CGFloat { lineHeight }
    var collapsedHunkHeaderHeight: CGFloat { lineHeight }

    static let standard = GitDiffRenderMetrics()
}

struct GitDiffRenderColumns: Hashable {
    let leftPane: CGRect
    let gutter: CGRect
    let rightPane: CGRect
}

struct GitDiffRenderLine: Identifiable {
    let id: String
    let segmentIndex: Int
    let side: GitDiffRenderSide
    let contentY: CGFloat
    let height: CGFloat
    let text: String
    let oldLine: Int?
    let newLine: Int?
    let kind: DiffLine.Kind
    let visualKind: GitDiffVisualKind
    let inlineSpans: [DiffInlineSpan]
}

struct GitDiffRenderBlock: Identifiable, Hashable {
    let id: String
    let segmentIndex: Int
    let visualKind: GitDiffVisualKind
    let oldContentRect: CGRect
    let newContentRect: CGRect
    let oldIsAnchor: Bool
    let newIsAnchor: Bool
}

struct GitDiffRenderSegment: Identifiable, Hashable {
    enum Kind: Hashable {
        case hunkHeader
        case context
        case change
    }

    let id: String
    let kind: Kind
    let visualKind: GitDiffVisualKind
    let virtualStart: CGFloat
    let virtualHeight: CGFloat
    let oldContentY: CGFloat
    let oldHeight: CGFloat
    let newContentY: CGFloat
    let newHeight: CGFloat
    let oldLineRange: Range<Int>
    let newLineRange: Range<Int>
    let blockRange: Range<Int>

    var virtualEnd: CGFloat { virtualStart + virtualHeight }
    var oldContentEnd: CGFloat { oldContentY + oldHeight }
    var newContentEnd: CGFloat { newContentY + newHeight }
}

struct GitDiffRenderLayout {
    let mode: DiffViewMode
    let metrics: GitDiffRenderMetrics
    let contentHeight: CGFloat
    let oldContentHeight: CGFloat
    let newContentHeight: CGFloat
    let virtualHeight: CGFloat
    let segments: [GitDiffRenderSegment]
    let oldLines: [GitDiffRenderLine]
    let newLines: [GitDiffRenderLine]
    let unifiedLines: [GitDiffRenderLine]
    let blocks: [GitDiffRenderBlock]

    static func build(
        from diff: StructuredFileDiff,
        mode: DiffViewMode,
        metrics: GitDiffRenderMetrics = .standard,
        granularity: GitDiffBlockGranularity = .fine,
        hunkHeaderExpansion: [String: CGFloat] = [:]
    ) -> GitDiffRenderLayout {
        switch mode {
        case .fluid:
            return buildFluid(
                from: diff,
                metrics: metrics,
                granularity: granularity,
                hunkHeaderExpansion: hunkHeaderExpansion
            )
        case .blocks:
            return buildBlocks(
                from: diff,
                metrics: metrics,
                granularity: granularity,
                hunkHeaderExpansion: hunkHeaderExpansion
            )
        case .unified:
            return buildUnified(from: diff, metrics: metrics, hunkHeaderExpansion: hunkHeaderExpansion)
        }
    }

    func columns(in bounds: CGRect) -> GitDiffRenderColumns {
        let available = max(bounds.width - metrics.horizontalPadding * 2 - metrics.gutterWidth, 100)
        let paneWidth = floor(available / 2)
        let leftPane = CGRect(
            x: metrics.horizontalPadding,
            y: bounds.minY,
            width: paneWidth,
            height: bounds.height
        )
        let gutter = CGRect(
            x: leftPane.maxX,
            y: bounds.minY,
            width: metrics.gutterWidth,
            height: bounds.height
        )
        let rightPane = CGRect(
            x: gutter.maxX,
            y: bounds.minY,
            width: paneWidth,
            height: bounds.height
        )
        return GitDiffRenderColumns(leftPane: leftPane, gutter: gutter, rightPane: rightPane)
    }

    func linearLines(_ lines: [GitDiffRenderLine], visible: CGRect, overscan: CGFloat = 80) -> ArraySlice<GitDiffRenderLine> {
        guard !lines.isEmpty else { return [] }
        let minY = visible.minY - overscan
        let maxY = visible.maxY + overscan
        var start = 0
        var end = lines.count
        while start < end {
            let mid = (start + end) / 2
            if lines[mid].contentY + lines[mid].height < minY {
                start = mid + 1
            } else {
                end = mid
            }
        }

        var stop = start
        while stop < lines.count, lines[stop].contentY <= maxY {
            stop += 1
        }
        return lines[start..<stop]
    }

    func fluidSegments(visible: CGRect, overscan: CGFloat = 240) -> ArraySlice<GitDiffRenderSegment> {
        guard !segments.isEmpty else { return [] }
        let minY = visible.minY - overscan
        let maxY = visible.maxY + overscan
        var start = 0
        var end = segments.count
        while start < end {
            let mid = (start + end) / 2
            if segments[mid].virtualEnd < minY {
                start = mid + 1
            } else {
                end = mid
            }
        }

        var stop = start
        while stop < segments.count, segments[stop].virtualStart <= maxY {
            stop += 1
        }
        return segments[start..<stop]
    }

    private static func buildUnified(
        from diff: StructuredFileDiff,
        metrics: GitDiffRenderMetrics,
        hunkHeaderExpansion: [String: CGFloat]
    ) -> GitDiffRenderLayout {
        var inlineQueues = unifiedInlineSpanQueues(for: diff)
        var y: CGFloat = 0
        var hunkIndex = 0
        let lines = diff.unifiedLines.enumerated().map { index, line in
            let key = UnifiedLineKey(kind: line.kind, text: line.text, oldLine: line.oldLine, newLine: line.newLine)
            let spans = popInlineSpans(for: key, queues: &inlineQueues)
            let id: String
            let height: CGFloat
            if line.kind == .hunkHeader {
                id = hunkHeaderID(forHunkIndex: hunkIndex)
                height = hunkHeaderHeight(id: id, metrics: metrics, expansion: hunkHeaderExpansion)
                hunkIndex += 1
            } else {
                id = "unified-\(index)"
                height = metrics.lineHeight
            }
            let renderLine = GitDiffRenderLine(
                id: id,
                segmentIndex: -1,
                side: .old,
                contentY: y,
                height: height,
                text: line.text,
                oldLine: line.oldLine,
                newLine: line.newLine,
                kind: line.kind,
                visualKind: visualKind(for: line.kind),
                inlineSpans: spans
            )
            y += height
            return renderLine
        }
        let height = y + metrics.bottomPadding
        return GitDiffRenderLayout(
            mode: .unified,
            metrics: metrics,
            contentHeight: height,
            oldContentHeight: height,
            newContentHeight: height,
            virtualHeight: height,
            segments: [],
            oldLines: [],
            newLines: [],
            unifiedLines: lines,
            blocks: []
        )
    }

    private static func buildBlocks(
        from diff: StructuredFileDiff,
        metrics: GitDiffRenderMetrics,
        granularity: GitDiffBlockGranularity,
        hunkHeaderExpansion: [String: CGFloat]
    ) -> GitDiffRenderLayout {
        var builder = SplitLayoutBuilder(mode: .blocks, metrics: metrics)
        var displayY: CGFloat = 0

        for hunk in diff.hunks {
            let headerID = hunkHeaderID(for: hunk)
            let headerHeight = hunkHeaderHeight(id: headerID, metrics: metrics, expansion: hunkHeaderExpansion)
            builder.appendHunkHeader(hunk.header, id: headerID, height: headerHeight, virtualY: displayY, oldY: displayY, newY: displayY)
            displayY += headerHeight

            for segment in hunk.segments {
                switch segment.kind {
                case .context:
                    let segmentIndex = builder.reserveSegmentIndex()
                    let start = displayY
                    for line in segment.contextLines {
                        builder.appendContextLine(line, oldY: displayY, newY: displayY, segmentIndex: segmentIndex)
                        displayY += metrics.lineHeight
                    }
                    builder.commitReservedSegment(
                        id: segment.id,
                        kind: .context,
                        visualKind: .context,
                        virtualStart: start,
                        virtualHeight: displayY - start,
                        oldY: start,
                        oldHeight: displayY - start,
                        newY: start,
                        newHeight: displayY - start
                    )
                case .change:
                    guard let change = segment.change else { continue }
                    let bands = changeBands(for: change, granularity: granularity)
                    for band in bands {
                        let start = displayY
                        let rowCount = max(band.linePairs.count, 1)
                        let height = CGFloat(rowCount) * metrics.lineHeight
                        let segmentIndex = builder.reserveSegmentIndex()
                        for (index, pair) in band.linePairs.enumerated() {
                            let rowY = start + CGFloat(index) * metrics.lineHeight
                            if let oldLine = pair.oldLine {
                                builder.appendOldLine(oldLine, y: rowY, segmentIndex: segmentIndex, visualKind: band.visualKind)
                            }
                            if let newLine = pair.newLine {
                                builder.appendNewLine(newLine, y: rowY, segmentIndex: segmentIndex, visualKind: band.visualKind)
                            }
                        }
                        builder.appendBlock(
                            id: blockID(for: change, band: band, totalBandCount: bands.count),
                            segmentIndex: segmentIndex,
                            visualKind: band.visualKind,
                            oldRect: CGRect(x: 0, y: start, width: 0, height: height),
                            newRect: CGRect(x: 0, y: start, width: 0, height: height),
                            oldIsAnchor: false,
                            newIsAnchor: false
                        )
                        builder.commitReservedSegment(
                            id: segmentID(for: segment, band: band, totalBandCount: bands.count),
                            kind: .change,
                            visualKind: band.visualKind,
                            virtualStart: start,
                            virtualHeight: height,
                            oldY: start,
                            oldHeight: height,
                            newY: start,
                            newHeight: height
                        )
                        displayY += height
                    }
                }
            }
        }

        return builder.finish(contentHeight: displayY + metrics.bottomPadding)
    }

    private static func buildFluid(
        from diff: StructuredFileDiff,
        metrics: GitDiffRenderMetrics,
        granularity: GitDiffBlockGranularity,
        hunkHeaderExpansion: [String: CGFloat]
    ) -> GitDiffRenderLayout {
        var builder = SplitLayoutBuilder(mode: .fluid, metrics: metrics)
        var virtualY: CGFloat = 0
        var oldY: CGFloat = 0
        var newY: CGFloat = 0

        for hunk in diff.hunks {
            let headerID = hunkHeaderID(for: hunk)
            let headerHeight = hunkHeaderHeight(id: headerID, metrics: metrics, expansion: hunkHeaderExpansion)
            builder.appendHunkHeader(hunk.header, id: headerID, height: headerHeight, virtualY: virtualY, oldY: oldY, newY: newY)
            virtualY += headerHeight
            oldY += headerHeight
            newY += headerHeight

            for segment in hunk.segments {
                switch segment.kind {
                case .context:
                    let segmentIndex = builder.reserveSegmentIndex()
                    let oldStart = oldY
                    let newStart = newY
                    let virtualStart = virtualY
                    for line in segment.contextLines {
                        builder.appendContextLine(line, oldY: oldY, newY: newY, segmentIndex: segmentIndex)
                        oldY += metrics.lineHeight
                        newY += metrics.lineHeight
                        virtualY += metrics.lineHeight
                    }
                    builder.commitReservedSegment(
                        id: segment.id,
                        kind: .context,
                        visualKind: .context,
                        virtualStart: virtualStart,
                        virtualHeight: virtualY - virtualStart,
                        oldY: oldStart,
                        oldHeight: oldY - oldStart,
                        newY: newStart,
                        newHeight: newY - newStart
                    )
                case .change:
                    guard let change = segment.change else { continue }
                    let bands = changeBands(for: change, granularity: granularity)
                    for band in bands {
                        let oldStart = oldY
                        let newStart = newY
                        let virtualStart = virtualY
                        let oldHeight = CGFloat(band.oldLines.count) * metrics.lineHeight
                        let newHeight = CGFloat(band.newLines.count) * metrics.lineHeight
                        let virtualHeight = max(oldHeight, newHeight, metrics.lineHeight)
                        let segmentIndex = builder.reserveSegmentIndex()

                        for oldLine in band.oldLines {
                            builder.appendOldLine(oldLine, y: oldY, segmentIndex: segmentIndex, visualKind: band.visualKind)
                            oldY += metrics.lineHeight
                        }
                        for newLine in band.newLines {
                            builder.appendNewLine(newLine, y: newY, segmentIndex: segmentIndex, visualKind: band.visualKind)
                            newY += metrics.lineHeight
                        }

                        builder.appendBlock(
                            id: blockID(for: change, band: band, totalBandCount: bands.count),
                            segmentIndex: segmentIndex,
                            visualKind: band.visualKind,
                            oldRect: blockRect(start: oldStart, height: oldHeight, anchorHeight: metrics.anchorHeight),
                            newRect: blockRect(start: newStart, height: newHeight, anchorHeight: metrics.anchorHeight),
                            oldIsAnchor: oldHeight == 0,
                            newIsAnchor: newHeight == 0
                        )
                        builder.commitReservedSegment(
                            id: segmentID(for: segment, band: band, totalBandCount: bands.count),
                            kind: .change,
                            visualKind: band.visualKind,
                            virtualStart: virtualStart,
                            virtualHeight: virtualHeight,
                            oldY: oldStart,
                            oldHeight: oldHeight,
                            newY: newStart,
                            newHeight: newHeight
                        )
                        virtualY += virtualHeight
                    }
                }
            }
        }

        return builder.finish(
            contentHeight: virtualY + metrics.bottomPadding,
            oldContentHeight: oldY,
            newContentHeight: newY,
            virtualHeight: virtualY
        )
    }

    private static func blockRect(start: CGFloat, height: CGFloat, anchorHeight: CGFloat) -> CGRect {
        if height == 0 {
            return CGRect(x: 0, y: start, width: 0, height: anchorHeight)
        }
        return CGRect(x: 0, y: start, width: 0, height: height)
    }

    static func hunkHeaderID(forHunkIndex index: Int) -> String {
        "hunk-\(index)|header"
    }

    static func hunkHeaderID(for hunk: DiffHunk) -> String {
        "\(hunk.id)|header"
    }

    static func hunkHeaderHeight(
        id: String,
        metrics: GitDiffRenderMetrics,
        expansion: [String: CGFloat]
    ) -> CGFloat {
        let progress = min(max(expansion[id] ?? 0, 0), 1)
        return metrics.collapsedHunkHeaderHeight
            + (metrics.lineHeight - metrics.collapsedHunkHeaderHeight) * progress
    }

    private static func changeBands(
        for change: ChangeBlock,
        granularity: GitDiffBlockGranularity
    ) -> [ChangeBand] {
        guard !change.linePairs.isEmpty else {
            return [ChangeBand(index: 0, visualKind: visualKind(for: change), linePairs: [])]
        }

        switch granularity {
        case .coarse:
            return [ChangeBand(index: 0, visualKind: visualKind(for: change), linePairs: change.linePairs)]
        case .fine:
            var bands: [ChangeBand] = []
            var currentKind = visualKind(for: change.linePairs[0].kind)
            var currentPairs: [DiffLinePair] = []

            func flush() {
                guard !currentPairs.isEmpty else { return }
                bands.append(ChangeBand(index: bands.count, visualKind: currentKind, linePairs: currentPairs))
                currentPairs = []
            }

            for pair in change.linePairs {
                let pairKind = visualKind(for: pair.kind)
                if pairKind != currentKind {
                    flush()
                    currentKind = pairKind
                }
                currentPairs.append(pair)
            }
            flush()
            return bands
        }
    }

    private static func blockID(for change: ChangeBlock, band: ChangeBand, totalBandCount: Int) -> String {
        totalBandCount == 1 ? change.id : "\(change.id)-band-\(band.index)"
    }

    private static func segmentID(for segment: DiffSegment, band: ChangeBand, totalBandCount: Int) -> String {
        totalBandCount == 1 ? segment.id : "\(segment.id)-band-\(band.index)"
    }

    private static func visualKind(for change: ChangeBlock) -> GitDiffVisualKind {
        if change.oldLines.isEmpty {
            return .addition
        }
        if change.newLines.isEmpty {
            return .deletion
        }
        return .modification
    }

    private static func visualKind(for pairKind: DiffLinePair.Kind) -> GitDiffVisualKind {
        switch pairKind {
        case .modified:
            return .modification
        case .deleted:
            return .deletion
        case .inserted:
            return .addition
        }
    }

    private static func visualKind(for lineKind: DiffLine.Kind) -> GitDiffVisualKind {
        switch lineKind {
        case .addition:
            return .addition
        case .deletion:
            return .deletion
        case .hunkHeader:
            return .hunkHeader
        default:
            return .context
        }
    }

    private struct ChangeBand: Hashable {
        let index: Int
        let visualKind: GitDiffVisualKind
        let linePairs: [DiffLinePair]

        var oldLines: [DiffTextLine] {
            linePairs.compactMap(\.oldLine)
        }

        var newLines: [DiffTextLine] {
            linePairs.compactMap(\.newLine)
        }
    }

    private struct UnifiedLineKey: Hashable {
        let kind: DiffLine.Kind
        let text: String
        let oldLine: Int?
        let newLine: Int?
    }

    private static func unifiedInlineSpanQueues(for diff: StructuredFileDiff) -> [UnifiedLineKey: [[DiffInlineSpan]]] {
        var queues: [UnifiedLineKey: [[DiffInlineSpan]]] = [:]
        for hunk in diff.hunks {
            for segment in hunk.segments {
                guard let change = segment.change else { continue }
                for pair in change.linePairs {
                    if let oldLine = pair.oldLine, !oldLine.inlineSpans.isEmpty {
                        queues[key(for: oldLine), default: []].append(oldLine.inlineSpans)
                    }
                    if let newLine = pair.newLine, !newLine.inlineSpans.isEmpty {
                        queues[key(for: newLine), default: []].append(newLine.inlineSpans)
                    }
                }
            }
        }
        return queues
    }

    private static func popInlineSpans(
        for key: UnifiedLineKey,
        queues: inout [UnifiedLineKey: [[DiffInlineSpan]]]
    ) -> [DiffInlineSpan] {
        guard var queue = queues[key], !queue.isEmpty else { return [] }
        let spans = queue.removeFirst()
        queues[key] = queue
        return spans
    }

    private static func key(for line: DiffTextLine) -> UnifiedLineKey {
        UnifiedLineKey(kind: line.kind, text: line.text, oldLine: line.oldLine, newLine: line.newLine)
    }
}

private struct SplitLayoutBuilder {
    let mode: DiffViewMode
    let metrics: GitDiffRenderMetrics
    private(set) var segments: [GitDiffRenderSegment] = []
    private(set) var oldLines: [GitDiffRenderLine] = []
    private(set) var newLines: [GitDiffRenderLine] = []
    private(set) var blocks: [GitDiffRenderBlock] = []
    private var reservedSegmentIndex: Int?
    private var reservedOldLineStart = 0
    private var reservedNewLineStart = 0
    private var reservedBlockStart = 0

    init(mode: DiffViewMode, metrics: GitDiffRenderMetrics) {
        self.mode = mode
        self.metrics = metrics
    }

    mutating func reserveSegmentIndex() -> Int {
        let index = segments.count
        reservedSegmentIndex = index
        reservedOldLineStart = oldLines.count
        reservedNewLineStart = newLines.count
        reservedBlockStart = blocks.count
        return index
    }

    mutating func commitReservedSegment(
        id: String,
        kind: GitDiffRenderSegment.Kind,
        visualKind: GitDiffVisualKind,
        virtualStart: CGFloat,
        virtualHeight: CGFloat,
        oldY: CGFloat,
        oldHeight: CGFloat,
        newY: CGFloat,
        newHeight: CGFloat
    ) {
        let segmentIndex = reservedSegmentIndex ?? segments.count
        for index in reservedBlockStart..<blocks.count where blocks[index].segmentIndex != segmentIndex {
            assertionFailure("Reserved block segment mismatch")
        }
        segments.append(GitDiffRenderSegment(
            id: id,
            kind: kind,
            visualKind: visualKind,
            virtualStart: virtualStart,
            virtualHeight: virtualHeight,
            oldContentY: oldY,
            oldHeight: oldHeight,
            newContentY: newY,
            newHeight: newHeight,
            oldLineRange: reservedOldLineStart..<oldLines.count,
            newLineRange: reservedNewLineStart..<newLines.count,
            blockRange: reservedBlockStart..<blocks.count
        ))
        reservedSegmentIndex = nil
    }

    mutating func appendHunkHeader(
        _ text: String,
        id: String,
        height: CGFloat,
        virtualY: CGFloat,
        oldY: CGFloat,
        newY: CGFloat
    ) {
        let segmentIndex = reserveSegmentIndex()
        let oldLine = syntheticLine(
            id: "\(id)-old",
            segmentIndex: segmentIndex,
            side: .old,
            text: text,
            oldLine: nil,
            newLine: nil,
            kind: .hunkHeader,
            y: oldY,
            height: height,
            visualKind: .hunkHeader
        )
        let newLine = syntheticLine(
            id: "\(id)-new",
            segmentIndex: segmentIndex,
            side: .new,
            text: text,
            oldLine: nil,
            newLine: nil,
            kind: .hunkHeader,
            y: newY,
            height: height,
            visualKind: .hunkHeader
        )
        oldLines.append(oldLine)
        newLines.append(newLine)
        commitReservedSegment(
            id: id,
            kind: .hunkHeader,
            visualKind: .hunkHeader,
            virtualStart: virtualY,
            virtualHeight: height,
            oldY: oldY,
            oldHeight: height,
            newY: newY,
            newHeight: height
        )
    }

    mutating func appendContextLine(_ line: DiffTextLine, oldY: CGFloat, newY: CGFloat, segmentIndex: Int) {
        appendOldLine(line, y: oldY, segmentIndex: segmentIndex, visualKind: .context)
        appendNewLine(line, y: newY, segmentIndex: segmentIndex, visualKind: .context)
    }

    mutating func appendOldLine(_ line: DiffTextLine, y: CGFloat, segmentIndex: Int, visualKind: GitDiffVisualKind) {
        oldLines.append(renderLine(from: line, side: .old, y: y, segmentIndex: segmentIndex, visualKind: visualKind))
    }

    mutating func appendNewLine(_ line: DiffTextLine, y: CGFloat, segmentIndex: Int, visualKind: GitDiffVisualKind) {
        newLines.append(renderLine(from: line, side: .new, y: y, segmentIndex: segmentIndex, visualKind: visualKind))
    }

    mutating func appendBlock(
        id: String,
        segmentIndex: Int,
        visualKind: GitDiffVisualKind,
        oldRect: CGRect,
        newRect: CGRect,
        oldIsAnchor: Bool,
        newIsAnchor: Bool
    ) {
        blocks.append(GitDiffRenderBlock(
            id: id,
            segmentIndex: segmentIndex,
            visualKind: visualKind,
            oldContentRect: oldRect,
            newContentRect: newRect,
            oldIsAnchor: oldIsAnchor,
            newIsAnchor: newIsAnchor
        ))
    }

    func finish(
        contentHeight: CGFloat,
        oldContentHeight: CGFloat? = nil,
        newContentHeight: CGFloat? = nil,
        virtualHeight: CGFloat? = nil
    ) -> GitDiffRenderLayout {
        GitDiffRenderLayout(
            mode: mode,
            metrics: metrics,
            contentHeight: contentHeight,
            oldContentHeight: oldContentHeight ?? contentHeight,
            newContentHeight: newContentHeight ?? contentHeight,
            virtualHeight: virtualHeight ?? contentHeight,
            segments: segments,
            oldLines: oldLines,
            newLines: newLines,
            unifiedLines: [],
            blocks: blocks
        )
    }

    private func renderLine(
        from line: DiffTextLine,
        side: GitDiffRenderSide,
        y: CGFloat,
        segmentIndex: Int,
        visualKind: GitDiffVisualKind
    ) -> GitDiffRenderLine {
        GitDiffRenderLine(
            id: "\(line.id)-\(side)",
            segmentIndex: segmentIndex,
            side: side,
            contentY: y,
            height: metrics.lineHeight,
            text: line.text,
            oldLine: side == .old ? line.oldLine : nil,
            newLine: side == .new ? line.newLine : nil,
            kind: line.kind,
            visualKind: visualKind,
            inlineSpans: line.inlineSpans
        )
    }

    private func syntheticLine(
        id: String,
        segmentIndex: Int,
        side: GitDiffRenderSide,
        text: String,
        oldLine: Int?,
        newLine: Int?,
        kind: DiffLine.Kind,
        y: CGFloat,
        height: CGFloat = GitDiffRenderMetrics.standard.lineHeight,
        visualKind: GitDiffVisualKind
    ) -> GitDiffRenderLine {
        GitDiffRenderLine(
            id: id,
            segmentIndex: segmentIndex,
            side: side,
            contentY: y,
            height: height,
            text: text,
            oldLine: oldLine,
            newLine: newLine,
            kind: kind,
            visualKind: visualKind,
            inlineSpans: []
        )
    }
}
