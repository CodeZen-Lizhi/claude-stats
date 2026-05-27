import AppKit

@MainActor
final class GitDiffRenderView: NSView {
    var contentHeightDidChange: (() -> Void)?

    private var diff: StructuredFileDiff?
    private var mode: DiffViewMode = .fluid
    private var granularity: GitDiffBlockGranularity = .fine
    private var viewportScrollY: CGFloat = 0
    private var hoveredHunkHeaderID: String?
    private var hoveredChangeBlockID: String?
    private var selectedChangeBlockID: String?
    private var hunkHeaderExpansion: [String: CGFloat] = [:]
    private var hunkHeaderAnimations: [String: HunkHeaderAnimation] = [:]
    private var hunkHeaderAnimationTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var layoutContainerWidth: CGFloat = 0
    private var renderLayout = GitDiffRenderLayout(
        mode: .fluid,
        metrics: .standard,
        contentHeight: 1,
        oldContentHeight: 1,
        newContentHeight: 1,
        virtualHeight: 1,
        segments: [],
        oldLines: [],
        newLines: [],
        unifiedLines: [],
        blocks: []
    )
    private let metrics = GitDiffRenderMetrics.standard
    private lazy var projector = GitDiffFluidProjector(metrics: metrics)
    private let font = GitDiffTextMeasurement.standardCodeFont()
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let hunkHeaderAnimationDuration: TimeInterval = 0.24

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var contentHeight: CGFloat {
        renderLayout.contentHeight
    }

    private var palette: GitDiffRenderPalette {
        GitDiffRenderPalette.standard(for: effectiveAppearance)
    }

    func update(diff: StructuredFileDiff, mode: DiffViewMode, granularity: GitDiffBlockGranularity) {
        if self.diff == diff, self.mode == mode, self.granularity == granularity {
            return
        }
        let diffChanged = self.diff != diff
        self.diff = diff
        self.mode = mode
        self.granularity = granularity
        if diffChanged {
            hoveredHunkHeaderID = nil
            hoveredChangeBlockID = nil
            selectedChangeBlockID = nil
            hunkHeaderExpansion = [:]
            hunkHeaderAnimations = [:]
            stopHunkHeaderAnimationTimerIfNeeded()
        }
        rebuildLayout()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredItem(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredHunkHeaderID != nil || hoveredChangeBlockID != nil else { return }
        hoveredHunkHeaderID = nil
        hoveredChangeBlockID = nil
        NSCursor.arrow.set()
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = hunkHeaderID(at: point) {
            toggleHunkHeader(id)
            return
        }
        if let id = changeBlockID(at: point) {
            selectedChangeBlockID = selectedChangeBlockID == id ? nil : id
            setNeedsDisplay(bounds)
            return
        }
        super.mouseDown(with: event)
    }

    func updateViewport(scrollY: CGFloat, size: CGSize) {
        let normalizedScrollY = max(scrollY, 0)
        if frame.size != size {
            setFrameSize(size)
        }
        if abs(layoutContainerWidth - size.width) > 0.5 {
            rebuildLayout(containerWidth: size.width)
        }
        guard viewportScrollY != normalizedScrollY else {
            setNeedsDisplay(bounds)
            return
        }
        viewportScrollY = normalizedScrollY
        setNeedsDisplay(bounds)
    }

    private func rebuildLayout(containerWidth: CGFloat? = nil) {
        guard let diff else { return }
        if let containerWidth {
            layoutContainerWidth = max(containerWidth, 1)
        } else if layoutContainerWidth <= 0 {
            layoutContainerWidth = 1200
        }
        let oldContentHeight = renderLayout.contentHeight
        renderLayout = GitDiffRenderLayout.build(
            from: diff,
            mode: mode,
            metrics: metrics,
            granularity: granularity,
            hunkHeaderExpansion: hunkHeaderExpansion,
            containerWidth: layoutContainerWidth,
            codeFont: font
        )
        if oldContentHeight != renderLayout.contentHeight {
            contentHeightDidChange?()
        }
    }

    private func updateHoveredItem(at point: CGPoint) {
        let hunkID = hunkHeaderID(at: point)
        let blockID = hunkID == nil ? changeBlockID(at: point) : nil
        guard hunkID != hoveredHunkHeaderID || blockID != hoveredChangeBlockID else { return }
        hoveredHunkHeaderID = hunkID
        hoveredChangeBlockID = blockID
        if hunkID != nil || blockID != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        setNeedsDisplay(bounds)
    }

    private func toggleHunkHeader(_ id: String) {
        let current = hunkHeaderExpansion[id] ?? 0
        let target: CGFloat = current < 0.5 ? 1 : 0
        hunkHeaderAnimations[id] = HunkHeaderAnimation(
            startProgress: current,
            targetProgress: target,
            startTime: ProcessInfo.processInfo.systemUptime,
            duration: hunkHeaderAnimationDuration
        )
        startHunkHeaderAnimationTimerIfNeeded()
    }

    private func startHunkHeaderAnimationTimerIfNeeded() {
        guard hunkHeaderAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickHunkHeaderAnimations()
            }
        }
        hunkHeaderAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHunkHeaderAnimationTimerIfNeeded() {
        guard hunkHeaderAnimations.isEmpty else { return }
        hunkHeaderAnimationTimer?.invalidate()
        hunkHeaderAnimationTimer = nil
    }

    private func tickHunkHeaderAnimations() {
        let now = ProcessInfo.processInfo.systemUptime
        var nextAnimations: [String: HunkHeaderAnimation] = [:]

        for (id, animation) in hunkHeaderAnimations {
            let rawProgress = min(max((now - animation.startTime) / animation.duration, 0), 1)
            let eased = HunkHeaderTimingCurve.default.value(at: CGFloat(rawProgress))
            let progress = animation.startProgress + (animation.targetProgress - animation.startProgress) * eased
            hunkHeaderExpansion[id] = progress
            if rawProgress < 1 {
                nextAnimations[id] = animation
            } else {
                hunkHeaderExpansion[id] = animation.targetProgress
            }
        }

        hunkHeaderAnimations = nextAnimations
        rebuildLayout()
        setNeedsDisplay(bounds)
        stopHunkHeaderAnimationTimerIfNeeded()
    }

    private func hunkHeaderID(at point: CGPoint) -> String? {
        switch renderLayout.mode {
        case .unified:
            return unifiedHunkHeaderID(at: point)
        case .blocks:
            return linearSplitHunkHeaderID(at: point)
        case .fluid:
            return fluidHunkHeaderID(at: point)
        }
    }

    private func unifiedHunkHeaderID(at point: CGPoint) -> String? {
        let sourceY = point.y + viewportScrollY
        let textRect = renderLayout.unifiedContentRect(in: bounds)
        guard textRect.minX <= point.x, point.x <= textRect.maxX else { return nil }
        for line in renderLayout.unifiedLines where line.kind == .hunkHeader {
            if sourceY >= line.contentY, sourceY <= line.contentY + line.height {
                return line.id
            }
        }
        return nil
    }

    private func linearSplitHunkHeaderID(at point: CGPoint) -> String? {
        let sourceY = point.y + viewportScrollY
        let columns = renderLayout.columns(in: bounds)
        guard point.x >= columns.leftPane.minX, point.x <= columns.rightPane.maxX else { return nil }
        for segment in renderLayout.segments where segment.kind == .hunkHeader {
            if sourceY >= segment.virtualStart, sourceY <= segment.virtualEnd {
                return segment.id
            }
        }
        return nil
    }

    private func fluidHunkHeaderID(at point: CGPoint) -> String? {
        let columns = renderLayout.columns(in: bounds)
        guard point.x >= columns.leftPane.minX, point.x <= columns.rightPane.maxX else { return nil }
        for segment in renderLayout.segments where segment.kind == .hunkHeader {
            let oldRect = projector.documentRect(
                for: CGRect(x: 0, y: segment.oldContentY, width: 0, height: segment.oldHeight),
                side: .old,
                in: segment,
                virtualScrollY: viewportScrollY,
                visibleMinY: 0,
                columns: columns
            )
            let newRect = projector.documentRect(
                for: CGRect(x: 0, y: segment.newContentY, width: 0, height: segment.newHeight),
                side: .new,
                in: segment,
                virtualScrollY: viewportScrollY,
                visibleMinY: 0,
                columns: columns
            )
            let hitRect = CGRect(
                x: columns.leftPane.minX,
                y: min(oldRect.minY, newRect.minY),
                width: columns.rightPane.maxX - columns.leftPane.minX,
                height: max(oldRect.maxY, newRect.maxY) - min(oldRect.minY, newRect.minY)
            )
            if hitRect.contains(point) {
                return segment.id
            }
        }
        return nil
    }

    private func changeBlockID(at point: CGPoint) -> String? {
        switch renderLayout.mode {
        case .unified:
            return unifiedChangeBlockID(at: point)
        case .blocks:
            return linearSplitChangeBlockID(at: point)
        case .fluid:
            return fluidChangeBlockID(at: point)
        }
    }

    private func unifiedChangeBlockID(at point: CGPoint) -> String? {
        let sourceY = point.y + viewportScrollY
        let textRect = renderLayout.unifiedContentRect(in: bounds)
        guard textRect.minX <= point.x, point.x <= textRect.maxX else { return nil }
        guard let index = renderLayout.unifiedLines.firstIndex(where: { line in
            sourceY >= line.contentY && sourceY <= line.contentY + line.height
        }) else { return nil }
        return unifiedChangeBlockID(containingLineAt: index)
    }

    private func linearSplitChangeBlockID(at point: CGPoint) -> String? {
        let sourceY = point.y + viewportScrollY
        let columns = renderLayout.columns(in: bounds)
        guard point.x >= columns.leftPane.minX, point.x <= columns.rightPane.maxX else { return nil }
        let regions = renderLayout.blocks.map { block in
            GitDiffInteractionRegion(
                id: block.id,
                visualKind: block.visualKind,
                rects: [GitDiffBlockGeometry.linearSpanRect(for: block, columns: columns)]
            )
        }
        return GitDiffInteractionHitTesting.hitTest(regions, at: CGPoint(x: point.x, y: sourceY))
    }

    private func fluidChangeBlockID(at point: CGPoint) -> String? {
        let columns = renderLayout.columns(in: bounds)
        guard point.x >= columns.leftPane.minX, point.x <= columns.rightPane.maxX else { return nil }
        let sourceVisible = CGRect(origin: .zero, size: bounds.size).offsetBy(dx: 0, dy: viewportScrollY)
        let visibleSegments = renderLayout.fluidSegments(visible: sourceVisible)

        for segment in visibleSegments.reversed() {
            for blockIndex in segment.blockRange.reversed() {
                let block = renderLayout.blocks[blockIndex]
                let projected = projector.projectedBlock(
                    block,
                    in: segment,
                    virtualScrollY: viewportScrollY,
                    visibleMinY: 0,
                    columns: columns
                )
                let region = GitDiffInteractionRegion(
                    id: block.id,
                    visualKind: block.visualKind,
                    rects: [
                        projected.oldRect,
                        projected.newRect,
                        connectorHitRect(for: projected, columns: columns)
                    ]
                )
                if GitDiffInteractionHitTesting.hitTest([region], at: point) != nil {
                    return block.id
                }
            }
        }
        return nil
    }

    private func unifiedChangeBlockID(for line: GitDiffRenderLine) -> String? {
        guard let index = renderLayout.unifiedLines.firstIndex(where: { $0.id == line.id }) else { return nil }
        return unifiedChangeBlockID(containingLineAt: index)
    }

    private func unifiedChangeBlockID(containingLineAt index: Int) -> String? {
        guard renderLayout.unifiedLines.indices.contains(index) else { return nil }
        let line = renderLayout.unifiedLines[index]
        guard isChangeVisualKind(line.visualKind) else { return nil }

        var start = index
        while start > renderLayout.unifiedLines.startIndex,
              isChangeVisualKind(renderLayout.unifiedLines[start - 1].visualKind) {
            start -= 1
        }
        return "unified-change-\(start)"
    }

    private func unifiedChangeRunRect(for id: String, in textRect: CGRect, scrollY: CGFloat) -> CGRect? {
        guard let startIndex = Int(id.replacingOccurrences(of: "unified-change-", with: "")),
              renderLayout.unifiedLines.indices.contains(startIndex),
              isChangeVisualKind(renderLayout.unifiedLines[startIndex].visualKind) else {
            return nil
        }

        var endIndex = startIndex
        while endIndex + 1 < renderLayout.unifiedLines.endIndex,
              isChangeVisualKind(renderLayout.unifiedLines[endIndex + 1].visualKind) {
            endIndex += 1
        }

        let startY = renderLayout.unifiedLines[startIndex].contentY - scrollY
        let endY = renderLayout.unifiedLines[endIndex].contentY + renderLayout.unifiedLines[endIndex].height - scrollY
        return CGRect(x: textRect.minX, y: startY, width: textRect.width, height: endY - startY)
    }

    private func isChangeVisualKind(_ kind: GitDiffVisualKind) -> Bool {
        kind == .addition || kind == .deletion || kind == .modification
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()

        let viewport = CGRect(origin: .zero, size: bounds.size)
        switch renderLayout.mode {
        case .unified:
            drawUnified(viewport, scrollY: viewportScrollY)
        case .blocks:
            drawBlocks(viewport, scrollY: viewportScrollY)
        case .fluid:
            drawFluid(viewport, virtualScrollY: viewportScrollY)
        }
    }

    private func drawUnified(_ visible: CGRect, scrollY: CGFloat) {
        let columns = renderLayout.columns(in: bounds)
        let textRect = renderLayout.unifiedContentRect(in: bounds)
        let sourceVisible = visible.offsetBy(dx: 0, dy: scrollY)
        for line in renderLayout.linearLines(renderLayout.unifiedLines, visible: sourceVisible) {
            let y = line.contentY - scrollY
            if line.kind == .hunkHeader {
                drawUnifiedHunkHeader(line, rect: textRect, y: y)
            } else {
                drawUnifiedLine(line, rect: textRect, y: y, drawBackground: true)
            }
        }
        drawUnifiedChangeBlockStroke(textRect: textRect, visible: visible, scrollY: scrollY)
        drawOverview(columns: columns, visible: visible)
    }

    private func drawBlocks(_ visible: CGRect, scrollY: CGFloat) {
        let columns = renderLayout.columns(in: bounds)
        let sourceVisible = visible.offsetBy(dx: 0, dy: scrollY)
        drawColumnChrome(columns, visible: visible)
        drawLinearBlockBackgrounds(columns: columns, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
        drawLinearSplitLines(renderLayout.oldLines, pane: columns.leftPane, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
        drawLinearSplitLines(renderLayout.newLines, pane: columns.rightPane, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
        drawOverview(columns: columns, visible: visible)
    }

    private func drawFluid(_ visible: CGRect, virtualScrollY: CGFloat) {
        let columns = renderLayout.columns(in: bounds)
        let sourceVisible = visible.offsetBy(dx: 0, dy: virtualScrollY)
        let visibleSegments = renderLayout.fluidSegments(visible: sourceVisible)

        drawColumnChrome(columns, visible: visible)
        drawFluidHunkHeaders(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidBlockBackgrounds(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidConnectors(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidBlockStrokes(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidLines(visibleSegments, side: .old, pane: columns.leftPane, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidLines(visibleSegments, side: .new, pane: columns.rightPane, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawOverview(columns: columns, visible: visible)
    }

    private func drawColumnChrome(_ columns: GitDiffRenderColumns, visible: CGRect) {
        palette.gutterFill.setFill()
        CGRect(x: columns.gutter.minX, y: visible.minY, width: columns.gutter.width, height: visible.height).fill()
    }

    private func drawOverview(columns: GitDiffRenderColumns, visible: CGRect) {
        guard columns.overviewLane.width > 0 else { return }
        let lane = columns.overviewLane.insetBy(dx: 0, dy: 4)
        guard lane.width > 0, lane.height > 0 else { return }

        palette.overviewTrackFill.setFill()
        lane.fill()

        let overview = GitDiffOverviewLayout.build(from: renderLayout, in: lane)
        for entry in overview.entries where entry.rect.intersects(visible) {
            palette.overviewFill(for: entry.visualKind).setFill()
            entry.rect.fill()
        }
    }

    private func drawLinearBlockBackgrounds(
        columns: GitDiffRenderColumns,
        visible: CGRect,
        sourceVisible: CGRect,
        scrollY: CGFloat
    ) {
        for block in renderLayout.blocks {
            let sourceRect = GitDiffBlockGeometry.linearSpanRect(for: block, columns: columns)
            guard sourceRect.intersects(sourceVisible) else { continue }
            let rect = sourceRect.offsetBy(dx: 0, dy: -scrollY)
            guard rect.intersects(visible) else { continue }
            palette.blockFill(for: block.visualKind, state: blockVisualState(for: block.id)).setFill()
            rect.fill()
            drawHoveredBlockStrokeIfNeeded(id: block.id, kind: block.visualKind, rects: [rect])
        }
    }

    private func drawFluidHunkHeaders(
        _ segments: ArraySlice<GitDiffRenderSegment>,
        columns: GitDiffRenderColumns,
        visible: CGRect,
        virtualScrollY: CGFloat
    ) {
        for segment in segments where segment.kind == .hunkHeader {
            let oldLine = segment.oldLineRange.first.map { renderLayout.oldLines[$0] }
            let newLine = segment.newLineRange.first.map { renderLayout.newLines[$0] }
            let oldRect = projector.documentRect(
                for: CGRect(x: 0, y: segment.oldContentY, width: 0, height: segment.oldHeight),
                side: .old,
                in: segment,
                virtualScrollY: virtualScrollY,
                visibleMinY: 0,
                columns: columns
            )
            let newRect = projector.documentRect(
                for: CGRect(x: 0, y: segment.newContentY, width: 0, height: segment.newHeight),
                side: .new,
                in: segment,
                virtualScrollY: virtualScrollY,
                visibleMinY: 0,
                columns: columns
            )
            drawSplitHunkHeader(
                id: segment.id,
                text: oldLine?.text ?? "",
                pane: columns.leftPane,
                y: oldRect.minY,
                height: oldRect.height,
                visible: visible
            )
            drawSplitHunkHeader(
                id: segment.id,
                text: newLine?.text ?? oldLine?.text ?? "",
                pane: columns.rightPane,
                y: newRect.minY,
                height: newRect.height,
                visible: visible
            )
        }
    }

    private func drawFluidBlockBackgrounds(
        _ segments: ArraySlice<GitDiffRenderSegment>,
        columns: GitDiffRenderColumns,
        visible: CGRect,
        virtualScrollY: CGFloat
    ) {
        for segment in segments {
            for blockIndex in segment.blockRange {
                let block = renderLayout.blocks[blockIndex]
                let projected = projector.projectedBlock(
                    block,
                    in: segment,
                    virtualScrollY: virtualScrollY,
                    visibleMinY: 0,
                    columns: columns
                )
                guard projected.oldRect.intersects(visible) || projected.newRect.intersects(visible) else { continue }
                palette.blockFill(for: block.visualKind, state: blockVisualState(for: block.id)).setFill()
                projected.oldRect.fill()
                projected.newRect.fill()
            }
        }
    }

    private func drawFluidConnectors(
        _ segments: ArraySlice<GitDiffRenderSegment>,
        columns: GitDiffRenderColumns,
        visible: CGRect,
        virtualScrollY: CGFloat
    ) {
        for segment in segments {
            for blockIndex in segment.blockRange {
                let block = renderLayout.blocks[blockIndex]
                let projected = projector.projectedBlock(
                    block,
                    in: segment,
                    virtualScrollY: virtualScrollY,
                    visibleMinY: 0,
                    columns: columns
                )
                let envelope = projected.connectorEnvelope(columns: columns)
                let connectorRect = connectorHitRect(for: projected, columns: columns)
                guard connectorRect.insetBy(dx: 0, dy: -metrics.lineHeight).intersects(visible) else { continue }
                let path = connectorPath(for: envelope)
                palette.connectorFill(for: envelope.visualKind, state: blockVisualState(for: block.id)).setFill()
                path.fill()
            }
        }
    }

    private func drawFluidBlockStrokes(
        _ segments: ArraySlice<GitDiffRenderSegment>,
        columns: GitDiffRenderColumns,
        visible: CGRect,
        virtualScrollY: CGFloat
    ) {
        for segment in segments {
            for blockIndex in segment.blockRange {
                let block = renderLayout.blocks[blockIndex]
                guard hoveredChangeBlockID == block.id else { continue }
                let projected = projector.projectedBlock(
                    block,
                    in: segment,
                    virtualScrollY: virtualScrollY,
                    visibleMinY: 0,
                    columns: columns
                )
                guard connectorHitRect(for: projected, columns: columns).insetBy(dx: 0, dy: -metrics.lineHeight).intersects(visible) else {
                    continue
                }
                drawBlockStroke(rect: projected.oldRect, kind: block.visualKind)
                drawBlockStroke(rect: projected.newRect, kind: block.visualKind)
                drawConnectorStroke(for: projected.connectorEnvelope(columns: columns))
            }
        }
    }

    private func drawLinearSplitLines(
        _ lines: [GitDiffRenderLine],
        pane: CGRect,
        visible: CGRect,
        sourceVisible: CGRect,
        scrollY: CGFloat
    ) {
        let clipPath = NSBezierPath(rect: CGRect(x: pane.minX, y: visible.minY, width: pane.width, height: visible.height))
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        for line in renderLayout.linearLines(lines, visible: sourceVisible) {
            let y = line.contentY - scrollY
            if line.kind == .hunkHeader {
                let segment = renderLayout.segments[line.segmentIndex]
                drawSplitHunkHeader(id: segment.id, text: line.text, pane: pane, y: y, height: line.height, visible: visible)
            } else {
                drawSplitLine(line, pane: pane, y: y, drawBackground: line.kind != .addition && line.kind != .deletion)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFluidLines(
        _ segments: ArraySlice<GitDiffRenderSegment>,
        side: GitDiffRenderSide,
        pane: CGRect,
        columns: GitDiffRenderColumns,
        visible: CGRect,
        virtualScrollY: CGFloat
    ) {
        let clipPath = NSBezierPath(rect: CGRect(x: pane.minX, y: visible.minY, width: pane.width, height: visible.height))
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        for segment in segments {
            guard segment.kind != .hunkHeader else { continue }
            let lineRange = side == .old ? segment.oldLineRange : segment.newLineRange
            let lines = side == .old ? renderLayout.oldLines : renderLayout.newLines
            for lineIndex in lineRange {
                let line = lines[lineIndex]
                let rect = projector.projectedLineRect(
                    line,
                    in: segment,
                    virtualScrollY: virtualScrollY,
                    visibleMinY: 0,
                    columns: columns
                )
                guard rect.intersects(visible) else { continue }
                drawSplitLine(line, pane: pane, y: rect.minY, drawBackground: false)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawUnifiedHunkHeader(_ line: GitDiffRenderLine, rect: CGRect, y: CGFloat) {
        let rowRect = CGRect(x: rect.minX, y: y, width: rect.width, height: line.height)
        guard rowRect.intersects(bounds) else { return }
        drawHunkHeaderBackground(id: line.id, rect: rowRect)
        drawHunkHeaderContent(id: line.id, text: line.text, rect: rowRect)
    }

    private func drawSplitHunkHeader(
        id: String,
        text: String,
        pane: CGRect,
        y: CGFloat,
        height: CGFloat,
        visible: CGRect
    ) {
        let rowRect = CGRect(x: pane.minX, y: y, width: pane.width, height: height)
        guard rowRect.intersects(visible) else { return }
        drawHunkHeaderBackground(id: id, rect: rowRect)
        drawHunkHeaderContent(id: id, text: text, rect: rowRect)
    }

    private func drawHunkHeaderBackground(id: String, rect: CGRect) {
        let fill = hoveredHunkHeaderID == id ? palette.hunkHeaderHoverFill : palette.hunkHeaderFill
        fill.setFill()
        rect.fill()
    }

    private func drawHunkHeaderContent(id: String, text: String, rect: CGRect) {
        let progress = hunkHeaderExpansion[id] ?? 0
        let iconAlpha = max(0, 1 - progress * 1.6)
        let textAlpha = min(max((progress - 0.35) / 0.65, 0), 1)

        if iconAlpha > 0.02 {
            drawHunkHeaderSymbol(in: rect, alpha: iconAlpha)
        }
        if textAlpha > 0.02 {
            drawText(
                text,
                x: rect.minX + metrics.lineNumberWidth + metrics.textLeftPadding,
                y: rect.minY + (rect.height - metrics.lineHeight) / 2,
                width: max(rect.width - metrics.lineNumberWidth - metrics.textLeftPadding - metrics.textRightPadding, 20),
                color: palette.secondaryText.withAlphaComponent(textAlpha),
                font: font
            )
        }
    }

    private func drawHunkHeaderSymbol(in rect: CGRect, alpha: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let extent: CGFloat = 5
        let arrowhead: CGFloat = 3.5
        let topLeft = CGPoint(x: center.x - extent, y: center.y - extent)
        let bottomRight = CGPoint(x: center.x + extent, y: center.y + extent)
        let path = NSBezierPath()
        path.lineWidth = 1.45
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: CGPoint(x: center.x - 1, y: center.y - 1))
        path.line(to: topLeft)
        path.move(to: topLeft)
        path.line(to: CGPoint(x: topLeft.x + arrowhead, y: topLeft.y))
        path.move(to: topLeft)
        path.line(to: CGPoint(x: topLeft.x, y: topLeft.y + arrowhead))

        path.move(to: CGPoint(x: center.x + 1, y: center.y + 1))
        path.line(to: bottomRight)
        path.move(to: bottomRight)
        path.line(to: CGPoint(x: bottomRight.x - arrowhead, y: bottomRight.y))
        path.move(to: bottomRight)
        path.line(to: CGPoint(x: bottomRight.x, y: bottomRight.y - arrowhead))

        palette.secondaryText.withAlphaComponent(alpha * 0.72).setStroke()
        path.stroke()
    }

    private func drawUnifiedLine(_ line: GitDiffRenderLine, rect: CGRect, y: CGFloat, drawBackground: Bool) {
        let rowRect = CGRect(x: rect.minX, y: y, width: rect.width, height: line.height)
        if drawBackground {
            let state = unifiedChangeBlockID(for: line).map(blockVisualState(for:)) ?? .normal
            palette.rowFill(for: line.kind, state: state).setFill()
            rowRect.fill()
        }

        drawLineNumber(line.oldLine, x: rowRect.minX, y: y)
        drawLineNumber(line.newLine, x: rowRect.minX + metrics.lineNumberWidth, y: y)
        drawText(
            marker(for: line.kind),
            x: rowRect.minX + metrics.lineNumberWidth * 2 + 4,
            y: y,
            width: 16,
            color: markerColor(for: line.kind),
            font: lineNumberFont
        )
        drawText(
            line.text.isEmpty ? " " : line.text,
            x: rowRect.minX + metrics.lineNumberWidth * 2 + 24,
            y: y,
            width: max(rowRect.width - metrics.lineNumberWidth * 2 - 24 - metrics.textRightPadding, 20),
            color: palette.textColor(for: line.kind),
            font: font,
            spans: line.inlineSpans,
            height: line.height,
            wraps: true
        )
    }

    private func drawSplitLine(_ line: GitDiffRenderLine, pane: CGRect, y: CGFloat, drawBackground: Bool) {
        let rowRect = CGRect(x: pane.minX, y: y, width: pane.width, height: line.height)
        if drawBackground {
            palette.rowFill(for: line.kind).setFill()
            rowRect.fill()
        }

        let number = line.side == .old ? line.oldLine : line.newLine
        drawLineNumber(number, x: rowRect.minX, y: y)
        drawText(
            line.text.isEmpty ? " " : line.text,
            x: rowRect.minX + metrics.lineNumberWidth + metrics.textLeftPadding,
            y: y,
            width: max(rowRect.width - metrics.lineNumberWidth - metrics.textLeftPadding - metrics.textRightPadding, 20),
            color: palette.textColor(for: line.kind),
            font: font,
            spans: line.inlineSpans,
            height: line.height,
            wraps: true
        )
    }

    private func drawUnifiedChangeBlockStroke(textRect: CGRect, visible: CGRect, scrollY: CGFloat) {
        guard let id = hoveredChangeBlockID,
              let rect = unifiedChangeRunRect(for: id, in: textRect, scrollY: scrollY),
              rect.intersects(visible),
              let firstLineIndex = Int(id.replacingOccurrences(of: "unified-change-", with: "")),
              renderLayout.unifiedLines.indices.contains(firstLineIndex) else {
            return
        }
        drawBlockStroke(rect: rect, kind: renderLayout.unifiedLines[firstLineIndex].visualKind)
    }

    private func drawLineNumber(_ number: Int?, x: CGFloat, y: CGFloat) {
        drawText(
            number.map(String.init) ?? "",
            x: x,
            y: y,
            width: metrics.lineNumberWidth - 8,
            color: palette.lineNumber,
            font: lineNumberFont,
            alignment: .right
        )
    }

    private func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        color: NSColor,
        font: NSFont,
        spans: [DiffInlineSpan] = [],
        alignment: NSTextAlignment = .left,
        height: CGFloat? = nil,
        wraps: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wraps ? .byCharWrapping : .byClipping
        paragraph.alignment = alignment
        paragraph.minimumLineHeight = metrics.lineHeight
        paragraph.maximumLineHeight = metrics.lineHeight
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        for span in spans {
            guard let range = nsRange(offset: span.offset, length: span.length, in: text) else { continue }
            attributed.addAttribute(.backgroundColor, value: palette.inlineFill(for: span.kind), range: range)
        }
        attributed.draw(
            with: CGRect(x: x, y: y + 2, width: width, height: max(height ?? metrics.lineHeight, metrics.lineHeight)),
            options: [.usesLineFragmentOrigin]
        )
    }

    private func blockVisualState(for id: String) -> GitDiffBlockVisualState {
        selectedChangeBlockID == id ? .selected : .normal
    }

    private func drawHoveredBlockStrokeIfNeeded(id: String, kind: GitDiffVisualKind, rects: [CGRect]) {
        guard hoveredChangeBlockID == id else { return }
        for rect in rects {
            drawBlockStroke(rect: rect, kind: kind)
        }
    }

    private func drawBlockStroke(rect: CGRect, kind: GitDiffVisualKind) {
        guard rect.width > 0, rect.height > 0 else { return }
        let stroke = NSBezierPath()
        stroke.lineWidth = 1
        stroke.move(to: NSPoint(x: rect.minX, y: rect.minY + 0.5))
        stroke.line(to: NSPoint(x: rect.maxX, y: rect.minY + 0.5))
        stroke.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
        stroke.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
        palette.blockStroke(for: kind).setStroke()
        stroke.stroke()
    }

    private func connectorHitRect(for projected: GitDiffProjectedBlock, columns: GitDiffRenderColumns) -> CGRect {
        CGRect(
            x: columns.leftPane.maxX - 1,
            y: min(projected.oldRect.minY, projected.newRect.minY),
            width: columns.rightPane.minX - columns.leftPane.maxX + 2,
            height: max(projected.oldRect.maxY, projected.newRect.maxY) - min(projected.oldRect.minY, projected.newRect.minY)
        )
    }

    private func drawConnectorStroke(for envelope: GitDiffConnectorEnvelope) {
        let path = connectorStrokePath(for: envelope)
        path.lineWidth = 1
        palette.blockStroke(for: envelope.visualKind).setStroke()
        path.stroke()
    }

    private func connectorPath(for envelope: GitDiffConnectorEnvelope) -> NSBezierPath {
        let path = NSBezierPath()
        let controlInset = min((envelope.rightX - envelope.leftX) * 0.55, 96)
        let leftTop = NSPoint(x: envelope.leftX, y: envelope.oldRect.minY)
        let leftBottom = NSPoint(x: envelope.leftX, y: envelope.oldRect.maxY)
        let rightTop = NSPoint(x: envelope.rightX, y: envelope.newRect.minY)
        let rightBottom = NSPoint(x: envelope.rightX, y: envelope.newRect.maxY)

        path.move(to: leftTop)
        path.curve(
            to: rightTop,
            controlPoint1: NSPoint(x: envelope.leftX + controlInset, y: leftTop.y),
            controlPoint2: NSPoint(x: envelope.rightX - controlInset, y: rightTop.y)
        )
        path.line(to: rightBottom)
        path.curve(
            to: leftBottom,
            controlPoint1: NSPoint(x: envelope.rightX - controlInset, y: rightBottom.y),
            controlPoint2: NSPoint(x: envelope.leftX + controlInset, y: leftBottom.y)
        )
        path.close()
        return path
    }

    private func connectorStrokePath(for envelope: GitDiffConnectorEnvelope) -> NSBezierPath {
        let path = NSBezierPath()
        let controlInset = min((envelope.rightX - envelope.leftX) * 0.55, 96)
        let leftTop = NSPoint(x: envelope.leftX, y: envelope.oldRect.minY + 0.5)
        let leftBottom = NSPoint(x: envelope.leftX, y: envelope.oldRect.maxY - 0.5)
        let rightTop = NSPoint(x: envelope.rightX, y: envelope.newRect.minY + 0.5)
        let rightBottom = NSPoint(x: envelope.rightX, y: envelope.newRect.maxY - 0.5)

        path.move(to: leftTop)
        path.curve(
            to: rightTop,
            controlPoint1: NSPoint(x: envelope.leftX + controlInset, y: leftTop.y),
            controlPoint2: NSPoint(x: envelope.rightX - controlInset, y: rightTop.y)
        )
        path.move(to: leftBottom)
        path.curve(
            to: rightBottom,
            controlPoint1: NSPoint(x: envelope.leftX + controlInset, y: leftBottom.y),
            controlPoint2: NSPoint(x: envelope.rightX - controlInset, y: rightBottom.y)
        )
        return path
    }

    private func nsRange(offset: Int, length: Int, in text: String) -> NSRange? {
        guard offset >= 0, length > 0,
              let start = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) else {
            return nil
        }
        return NSRange(start..<end, in: text)
    }

    private func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition:
            return "+"
        case .deletion:
            return "-"
        case .hunkHeader:
            return "@"
        default:
            return " "
        }
    }

    private func markerColor(for kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .addition, .deletion:
            return palette.primaryText
        case .hunkHeader:
            return palette.secondaryText
        default:
            return palette.lineNumber
        }
    }
}

private struct HunkHeaderAnimation {
    let startProgress: CGFloat
    let targetProgress: CGFloat
    let startTime: TimeInterval
    let duration: TimeInterval
}

private struct HunkHeaderTimingCurve {
    static let `default` = HunkHeaderTimingCurve(
        controlPoint1: CGPoint(x: 0.25, y: 0.1),
        controlPoint2: CGPoint(x: 0.25, y: 1)
    )

    let controlPoint1: CGPoint
    let controlPoint2: CGPoint

    func value(at x: CGFloat) -> CGFloat {
        let clampedX = min(max(x, 0), 1)
        var low: CGFloat = 0
        var high: CGFloat = 1
        var t = clampedX
        for _ in 0..<12 {
            t = (low + high) / 2
            if cubic(t, p1: controlPoint1.x, p2: controlPoint2.x) < clampedX {
                low = t
            } else {
                high = t
            }
        }
        return cubic(t, p1: controlPoint1.y, p2: controlPoint2.y)
    }

    private func cubic(_ t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * t * p1
            + 3 * oneMinusT * t * t * p2
            + t * t * t
    }
}
