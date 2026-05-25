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
