import AppKit

@MainActor
final class GitDiffRenderView: NSView {
    var contentHeightDidChange: (() -> Void)?

    private var diff: StructuredFileDiff?
    private var mode: DiffViewMode = .fluid
    private var granularity: GitDiffBlockGranularity = .fine
    private var viewportScrollY: CGFloat = 0
    private var hoveredHunkHeaderID: String?
    private var hunkHeaderExpansion: [String: CGFloat] = [:]
    private var hunkHeaderAnimations: [String: HunkHeaderAnimation] = [:]
    private var hunkHeaderAnimationTimer: Timer?
    private var trackingArea: NSTrackingArea?
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
    private let palette = GitDiffRenderPalette.standard
    private lazy var projector = GitDiffFluidProjector(metrics: metrics)
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let hunkHeaderAnimationDuration: TimeInterval = 0.24

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var contentHeight: CGFloat {
        renderLayout.contentHeight
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
            hunkHeaderExpansion = [:]
            hunkHeaderAnimations = [:]
            stopHunkHeaderAnimationTimerIfNeeded()
        }
        rebuildLayout()
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
        updateHoveredHunkHeader(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredHunkHeaderID != nil else { return }
        hoveredHunkHeaderID = nil
        NSCursor.arrow.set()
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = hunkHeaderID(at: point) else {
            super.mouseDown(with: event)
            return
        }
        toggleHunkHeader(id)
    }

    func updateViewport(scrollY: CGFloat, size: CGSize) {
        let normalizedScrollY = max(scrollY, 0)
        if frame.size != size {
            setFrameSize(size)
        }
        guard viewportScrollY != normalizedScrollY else {
            setNeedsDisplay(bounds)
            return
        }
        viewportScrollY = normalizedScrollY
        setNeedsDisplay(bounds)
    }

    private func rebuildLayout() {
        guard let diff else { return }
        let oldContentHeight = renderLayout.contentHeight
        renderLayout = GitDiffRenderLayout.build(
            from: diff,
            mode: mode,
            metrics: metrics,
            granularity: granularity,
            hunkHeaderExpansion: hunkHeaderExpansion
        )
        if oldContentHeight != renderLayout.contentHeight {
            contentHeightDidChange?()
        }
    }

    private func updateHoveredHunkHeader(at point: CGPoint) {
        let id = hunkHeaderID(at: point)
        guard id != hoveredHunkHeaderID else { return }
        hoveredHunkHeaderID = id
        if id == nil {
            NSCursor.arrow.set()
        } else {
            NSCursor.pointingHand.set()
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
            self?.tickHunkHeaderAnimations()
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
        let textRect = bounds.insetBy(dx: metrics.horizontalPadding, dy: 0)
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
        let textRect = bounds.insetBy(dx: metrics.horizontalPadding, dy: 0)
        let sourceVisible = visible.offsetBy(dx: 0, dy: scrollY)
        for line in renderLayout.linearLines(renderLayout.unifiedLines, visible: sourceVisible) {
            let y = line.contentY - scrollY
            if line.kind == .hunkHeader {
                drawUnifiedHunkHeader(line, rect: textRect, y: y)
            } else {
                drawUnifiedLine(line, rect: textRect, y: y, drawBackground: true)
            }
        }
    }

    private func drawBlocks(_ visible: CGRect, scrollY: CGFloat) {
        let columns = renderLayout.columns(in: bounds)
        let sourceVisible = visible.offsetBy(dx: 0, dy: scrollY)
        drawColumnChrome(columns, visible: visible)
        drawLinearBlockBackgrounds(columns: columns, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
        drawLinearSplitLines(renderLayout.oldLines, pane: columns.leftPane, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
        drawLinearSplitLines(renderLayout.newLines, pane: columns.rightPane, visible: visible, sourceVisible: sourceVisible, scrollY: scrollY)
    }

    private func drawFluid(_ visible: CGRect, virtualScrollY: CGFloat) {
        let columns = renderLayout.columns(in: bounds)
        let sourceVisible = visible.offsetBy(dx: 0, dy: virtualScrollY)
        let visibleSegments = renderLayout.fluidSegments(visible: sourceVisible)

        drawColumnChrome(columns, visible: visible)
        drawFluidHunkHeaders(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidBlockBackgrounds(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidConnectors(visibleSegments, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidLines(visibleSegments, side: .old, pane: columns.leftPane, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
        drawFluidLines(visibleSegments, side: .new, pane: columns.rightPane, columns: columns, visible: visible, virtualScrollY: virtualScrollY)
    }

    private func drawColumnChrome(_ columns: GitDiffRenderColumns, visible: CGRect) {
        palette.separator.setFill()
        CGRect(x: columns.gutter.midX - 0.5, y: visible.minY, width: 1, height: visible.height).fill()
    }

    private func drawLinearBlockBackgrounds(
        columns: GitDiffRenderColumns,
        visible: CGRect,
        sourceVisible: CGRect,
        scrollY: CGFloat
    ) {
        for block in renderLayout.blocks {
            let oldSourceRect = CGRect(x: columns.leftPane.minX, y: block.oldContentRect.minY, width: columns.leftPane.width, height: block.oldContentRect.height)
            let newSourceRect = CGRect(x: columns.rightPane.minX, y: block.newContentRect.minY, width: columns.rightPane.width, height: block.newContentRect.height)
            guard oldSourceRect.intersects(sourceVisible) || newSourceRect.intersects(sourceVisible) else { continue }
            let oldRect = oldSourceRect.offsetBy(dx: 0, dy: -scrollY)
            let newRect = newSourceRect.offsetBy(dx: 0, dy: -scrollY)
            guard oldRect.intersects(visible) || newRect.intersects(visible) else { continue }
            palette.blockFill(for: block.visualKind).setFill()
            oldRect.fill()
            newRect.fill()
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
                palette.blockFill(for: block.visualKind).setFill()
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
                let connectorRect = CGRect(
                    x: columns.leftPane.maxX - 1,
                    y: min(projected.oldRect.minY, projected.newRect.minY),
                    width: columns.rightPane.minX - columns.leftPane.maxX + 2,
                    height: max(projected.oldRect.maxY, projected.newRect.maxY) - min(projected.oldRect.minY, projected.newRect.minY)
                )
                guard connectorRect.insetBy(dx: 0, dy: -metrics.lineHeight).intersects(visible) else { continue }
                let path = connectorPath(for: envelope)
                palette.connectorFill(for: envelope.visualKind).setFill()
                path.fill()
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
                width: max(rect.width - metrics.lineNumberWidth - metrics.textLeftPadding * 2, 20),
                color: palette.secondaryText.withAlphaComponent(textAlpha),
                font: font
            )
        }
    }

    private func drawHunkHeaderSymbol(in rect: CGRect, alpha: CGFloat) {
        guard let image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: nil
        ) else { return }
        let configured = image.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? image
        let size = configured.size
        let target = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        configured.draw(in: target, from: .zero, operation: .sourceOver, fraction: alpha * 0.55)
    }

    private func drawUnifiedLine(_ line: GitDiffRenderLine, rect: CGRect, y: CGFloat, drawBackground: Bool) {
        let rowRect = CGRect(x: rect.minX, y: y, width: rect.width, height: line.height)
        if drawBackground {
            palette.rowFill(for: line.kind).setFill()
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
            width: max(rowRect.width - metrics.lineNumberWidth * 2 - 24, 20),
            color: palette.textColor(for: line.kind),
            font: font,
            spans: line.inlineSpans
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
            width: max(rowRect.width - metrics.lineNumberWidth - metrics.textLeftPadding, 20),
            color: palette.textColor(for: line.kind),
            font: font,
            spans: line.inlineSpans
        )
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
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = alignment
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
            with: CGRect(x: x, y: y + 2, width: width, height: metrics.lineHeight),
            options: [.usesLineFragmentOrigin]
        )
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
