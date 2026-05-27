import CoreGraphics

/// Shared geometry for git graph rows. The rail keeps a stable full width for
/// drawing, while row content starts after the rightmost active lane on that row.
struct GitGraphRowGeometry {
    static let defaultAvatarGapAfterLane: CGFloat = 20

    let laneSpacing: CGFloat
    let railPad: CGFloat
    let avatarGapAfterLane: CGFloat

    init(laneSpacing: CGFloat,
         railPad: CGFloat,
         avatarGapAfterLane: CGFloat = Self.defaultAvatarGapAfterLane) {
        self.laneSpacing = laneSpacing
        self.railPad = railPad
        self.avatarGapAfterLane = avatarGapAfterLane
    }

    func laneX(_ column: Int) -> CGFloat {
        railPad + CGFloat(column) * laneSpacing
    }

    func railWidth(maxColumn: Int) -> CGFloat {
        CGFloat(maxColumn) * laneSpacing + railPad * 2
    }

    func contentLeading(for row: GraphLayout.Row) -> CGFloat {
        laneX(rightmostActiveColumn(for: row)) + avatarGapAfterLane
    }

    var workingTreeContentLeading: CGFloat {
        laneX(0) + avatarGapAfterLane
    }

    func rightmostActiveColumn(for row: GraphLayout.Row) -> Int {
        var column = row.column
        for lane in row.passThrough {
            column = max(column, lane.column)
        }
        for edge in row.edgesDown {
            column = max(column, edge.fromColumn, edge.toColumn)
        }
        return column
    }
}
