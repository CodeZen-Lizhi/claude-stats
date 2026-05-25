import CoreGraphics
import Foundation

struct GitDiffOverviewEntry: Hashable {
    let visualKind: GitDiffVisualKind
    let sourceY: CGFloat
    let sourceHeight: CGFloat
    let rect: CGRect
}

struct GitDiffOverviewLayout: Hashable {
    let entries: [GitDiffOverviewEntry]

    static func build(
        from layout: GitDiffRenderLayout,
        in lane: CGRect,
        minEntryHeight: CGFloat = 2
    ) -> GitDiffOverviewLayout {
        guard lane.width > 0, lane.height > 0 else {
            return GitDiffOverviewLayout(entries: [])
        }

        let sourceHeight = max(layout.contentHeight, layout.virtualHeight, 1)
        let entries: [GitDiffOverviewEntry]
        switch layout.mode {
        case .fluid, .blocks:
            entries = layout.blocks.compactMap { block in
                guard block.segmentIndex >= 0, block.segmentIndex < layout.segments.count else { return nil }
                let segment = layout.segments[block.segmentIndex]
                return entry(
                    kind: block.visualKind,
                    y: segment.virtualStart,
                    height: max(segment.virtualHeight, layout.metrics.lineHeight),
                    sourceHeight: sourceHeight,
                    lane: lane,
                    minEntryHeight: minEntryHeight
                )
            }
        case .unified:
            entries = unifiedEntries(from: layout, sourceHeight: sourceHeight, lane: lane, minEntryHeight: minEntryHeight)
        }

        return GitDiffOverviewLayout(entries: entries)
    }

    private static func unifiedEntries(
        from layout: GitDiffRenderLayout,
        sourceHeight: CGFloat,
        lane: CGRect,
        minEntryHeight: CGFloat
    ) -> [GitDiffOverviewEntry] {
        var entries: [GitDiffOverviewEntry] = []
        var currentKind: GitDiffVisualKind?
        var currentStart: CGFloat = 0
        var currentEnd: CGFloat = 0

        func flush() {
            guard let currentKind else { return }
            entries.append(entry(
                kind: currentKind,
                y: currentStart,
                height: max(currentEnd - currentStart, layout.metrics.lineHeight),
                sourceHeight: sourceHeight,
                lane: lane,
                minEntryHeight: minEntryHeight
            ))
        }

        for line in layout.unifiedLines {
            guard line.visualKind == .addition || line.visualKind == .deletion || line.visualKind == .modification else {
                flush()
                currentKind = nil
                continue
            }
            if line.visualKind != currentKind {
                flush()
                currentKind = line.visualKind
                currentStart = line.contentY
            }
            currentEnd = line.contentY + line.height
        }
        flush()
        return entries
    }

    private static func entry(
        kind: GitDiffVisualKind,
        y: CGFloat,
        height: CGFloat,
        sourceHeight: CGFloat,
        lane: CGRect,
        minEntryHeight: CGFloat
    ) -> GitDiffOverviewEntry {
        let scale = lane.height / sourceHeight
        let scaledHeight = min(max(height * scale, minEntryHeight), lane.height)
        let scaledY = min(max(y * scale, 0), max(lane.height - scaledHeight, 0))
        let rect = CGRect(
            x: lane.minX,
            y: lane.minY + scaledY,
            width: lane.width,
            height: scaledHeight
        )
        return GitDiffOverviewEntry(visualKind: kind, sourceY: y, sourceHeight: height, rect: rect)
    }
}
