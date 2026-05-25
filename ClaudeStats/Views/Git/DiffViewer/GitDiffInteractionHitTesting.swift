import CoreGraphics
import Foundation

struct GitDiffInteractionRegion: Hashable {
    let id: String
    let visualKind: GitDiffVisualKind
    let rects: [CGRect]
}

enum GitDiffInteractionHitTesting {
    static func hitTest(_ regions: [GitDiffInteractionRegion], at point: CGPoint) -> String? {
        for region in regions.reversed() {
            if region.rects.contains(where: { $0.contains(point) }) {
                return region.id
            }
        }
        return nil
    }
}

enum GitDiffBlockGeometry {
    static func linearSpanRect(for block: GitDiffRenderBlock, columns: GitDiffRenderColumns) -> CGRect {
        let minY = min(block.oldContentRect.minY, block.newContentRect.minY)
        let maxY = max(block.oldContentRect.maxY, block.newContentRect.maxY)
        return CGRect(
            x: columns.leftPane.minX,
            y: minY,
            width: max(columns.rightPane.maxX - columns.leftPane.minX, 0),
            height: max(maxY - minY, 0)
        )
    }
}
