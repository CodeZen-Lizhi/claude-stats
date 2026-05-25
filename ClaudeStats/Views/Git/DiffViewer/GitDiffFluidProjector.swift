import CoreGraphics

struct GitDiffProjectedBlock: Hashable {
    let block: GitDiffRenderBlock
    let oldRect: CGRect
    let newRect: CGRect
    let oldIsAnchor: Bool
    let newIsAnchor: Bool

    var visualKind: GitDiffVisualKind { block.visualKind }

    func connectorEnvelope(columns: GitDiffRenderColumns) -> GitDiffConnectorEnvelope {
        GitDiffConnectorEnvelope(
            oldRect: oldRect,
            newRect: newRect,
            leftX: columns.leftPane.maxX - 1,
            rightX: columns.rightPane.minX + 1,
            visualKind: visualKind
        )
    }
}

struct GitDiffConnectorEnvelope: Hashable {
    let oldRect: CGRect
    let newRect: CGRect
    let leftX: CGFloat
    let rightX: CGFloat
    let visualKind: GitDiffVisualKind
}

struct GitDiffFluidProjector {
    let metrics: GitDiffRenderMetrics

    init(metrics: GitDiffRenderMetrics = .standard) {
        self.metrics = metrics
    }

    func sideOffset(for segment: GitDiffRenderSegment, side: GitDiffRenderSide, virtualScrollY: CGFloat) -> CGFloat {
        let sideHeight = height(for: segment, side: side)
        guard sideHeight > 0 else { return 0 }
        if virtualScrollY <= segment.virtualStart {
            return 0
        }
        if virtualScrollY >= segment.virtualEnd {
            return sideHeight
        }
        return progress(for: segment, virtualScrollY: virtualScrollY) * sideHeight
    }

    func sideScreenTop(for segment: GitDiffRenderSegment, side: GitDiffRenderSide, virtualScrollY: CGFloat) -> CGFloat {
        let sideHeight = height(for: segment, side: side)
        if virtualScrollY <= segment.virtualStart {
            return segment.virtualStart - virtualScrollY
        }
        if virtualScrollY >= segment.virtualEnd {
            return segment.virtualEnd - virtualScrollY - sideHeight
        }
        return -progress(for: segment, virtualScrollY: virtualScrollY) * sideHeight
    }

    func screenRect(
        for contentRect: CGRect,
        side: GitDiffRenderSide,
        in segment: GitDiffRenderSegment,
        virtualScrollY: CGFloat,
        columns: GitDiffRenderColumns
    ) -> CGRect {
        let pane = side == .old ? columns.leftPane : columns.rightPane
        let sideStart = start(for: segment, side: side)
        let y = sideScreenTop(for: segment, side: side, virtualScrollY: virtualScrollY) + contentRect.minY - sideStart
        return CGRect(x: pane.minX, y: y, width: pane.width, height: contentRect.height)
    }

    func documentRect(
        for contentRect: CGRect,
        side: GitDiffRenderSide,
        in segment: GitDiffRenderSegment,
        virtualScrollY: CGFloat,
        visibleMinY: CGFloat,
        columns: GitDiffRenderColumns
    ) -> CGRect {
        var rect = screenRect(
            for: contentRect,
            side: side,
            in: segment,
            virtualScrollY: virtualScrollY,
            columns: columns
        )
        rect.origin.y += visibleMinY
        return rect
    }

    func projectedBlock(
        _ block: GitDiffRenderBlock,
        in segment: GitDiffRenderSegment,
        virtualScrollY: CGFloat,
        visibleMinY: CGFloat,
        columns: GitDiffRenderColumns
    ) -> GitDiffProjectedBlock {
        GitDiffProjectedBlock(
            block: block,
            oldRect: documentRect(
                for: block.oldContentRect,
                side: .old,
                in: segment,
                virtualScrollY: virtualScrollY,
                visibleMinY: visibleMinY,
                columns: columns
            ),
            newRect: documentRect(
                for: block.newContentRect,
                side: .new,
                in: segment,
                virtualScrollY: virtualScrollY,
                visibleMinY: visibleMinY,
                columns: columns
            ),
            oldIsAnchor: block.oldIsAnchor,
            newIsAnchor: block.newIsAnchor
        )
    }

    func projectedLineRect(
        _ line: GitDiffRenderLine,
        in segment: GitDiffRenderSegment,
        virtualScrollY: CGFloat,
        visibleMinY: CGFloat,
        columns: GitDiffRenderColumns
    ) -> CGRect {
        let contentRect = CGRect(x: 0, y: line.contentY, width: 0, height: line.height)
        return documentRect(
            for: contentRect,
            side: line.side,
            in: segment,
            virtualScrollY: virtualScrollY,
            visibleMinY: visibleMinY,
            columns: columns
        )
    }

    private func progress(for segment: GitDiffRenderSegment, virtualScrollY: CGFloat) -> CGFloat {
        guard segment.virtualHeight > 0 else { return 0 }
        return min(max((virtualScrollY - segment.virtualStart) / segment.virtualHeight, 0), 1)
    }

    private func height(for segment: GitDiffRenderSegment, side: GitDiffRenderSide) -> CGFloat {
        switch side {
        case .old:
            return segment.oldHeight
        case .new:
            return segment.newHeight
        }
    }

    private func start(for segment: GitDiffRenderSegment, side: GitDiffRenderSide) -> CGFloat {
        switch side {
        case .old:
            return segment.oldContentY
        case .new:
            return segment.newContentY
        }
    }
}
