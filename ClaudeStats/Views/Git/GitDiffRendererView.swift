import AppKit
import SwiftUI

struct GitDiffRendererView: NSViewRepresentable {
    let diff: StructuredFileDiff
    let mode: DiffViewMode

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        AppScrollbars.configure(scrollView)

        let renderView = DiffRenderView()
        renderView.update(diff: diff, mode: mode)
        scrollView.documentView = renderView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        AppScrollbars.configure(scrollView)
        guard let renderView = scrollView.documentView as? DiffRenderView else { return }
        renderView.update(diff: diff, mode: mode)
    }
}

private final class DiffRenderView: NSView {
    private enum Side {
        case old
        case new
    }

    private struct PositionedLine {
        let side: Side
        let y: CGFloat
        let text: String
        let oldLine: Int?
        let newLine: Int?
        let kind: DiffLine.Kind
        let inlineSpans: [DiffInlineSpan]
    }

    private struct Connector {
        let oldY: CGFloat
        let oldHeight: CGFloat
        let newY: CGFloat
        let newHeight: CGFloat
    }

    private struct Layout {
        let contentHeight: CGFloat
        let syncMap: FluidSyncMap?
        let oldLines: [PositionedLine]
        let newLines: [PositionedLine]
        let unifiedLines: [PositionedLine]
        let connectors: [Connector]
    }

    private struct UnifiedLineKey: Hashable {
        let kind: DiffLine.Kind
        let text: String
        let oldLine: Int?
        let newLine: Int?
    }

    private struct Columns {
        let left: CGRect
        let right: CGRect
        let gutter: CGRect
    }

    private static let lineHeight: CGFloat = 18
    private static let gutterWidth: CGFloat = 78
    private static let lineNumberWidth: CGFloat = 46
    private static let horizontalPadding: CGFloat = 14
    private static let textLeftPadding: CGFloat = 8
    private static let bottomPadding: CGFloat = 24

    private var diff: StructuredFileDiff?
    private var mode: DiffViewMode = .fluid
    private var renderLayout = Layout(contentHeight: 1, syncMap: nil, oldLines: [], newLines: [], unifiedLines: [], connectors: [])
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    override var isFlipped: Bool { true }

    func update(diff: StructuredFileDiff, mode: DiffViewMode) {
        self.diff = diff
        self.mode = mode
        rebuildLayout()
        updateFrameHeight()
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateFrameHeight()
    }

    override func layout() {
        super.layout()
        updateFrameHeight()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        switch mode {
        case .unified:
            drawUnified(visibleRect)
        case .blocks:
            drawSplit(visibleRect, fluid: false)
        case .fluid:
            drawSplit(visibleRect, fluid: true)
        }
    }

    private func rebuildLayout() {
        guard let diff else {
            renderLayout = Layout(contentHeight: 1, syncMap: nil, oldLines: [], newLines: [], unifiedLines: [], connectors: [])
            return
        }

        switch mode {
        case .unified:
            renderLayout = buildUnifiedLayout(diff)
        case .blocks:
            renderLayout = buildBlocksLayout(diff)
        case .fluid:
            renderLayout = buildFluidLayout(diff)
        }
    }

    private func updateFrameHeight() {
        guard let scrollView = enclosingScrollView else { return }
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(renderLayout.contentHeight, scrollView.contentView.bounds.height + 1)
        if frame.size.width != width || frame.size.height != height {
            setFrameSize(NSSize(width: width, height: height))
        }
    }

    private func buildUnifiedLayout(_ diff: StructuredFileDiff) -> Layout {
        var inlineQueues = unifiedInlineSpanQueues(for: diff)
        let lines = diff.unifiedLines.enumerated().map { index, line in
            let key = UnifiedLineKey(kind: line.kind, text: line.text, oldLine: line.oldLine, newLine: line.newLine)
            let spans = popInlineSpans(for: key, queues: &inlineQueues)
            return PositionedLine(
                side: .old,
                y: CGFloat(index) * Self.lineHeight,
                text: line.text,
                oldLine: line.oldLine,
                newLine: line.newLine,
                kind: line.kind,
                inlineSpans: spans
            )
        }
        return Layout(
            contentHeight: CGFloat(lines.count) * Self.lineHeight + Self.bottomPadding,
            syncMap: nil,
            oldLines: [],
            newLines: [],
            unifiedLines: lines,
            connectors: []
        )
    }

    private func unifiedInlineSpanQueues(for diff: StructuredFileDiff) -> [UnifiedLineKey: [[DiffInlineSpan]]] {
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

    private func popInlineSpans(
        for key: UnifiedLineKey,
        queues: inout [UnifiedLineKey: [[DiffInlineSpan]]]
    ) -> [DiffInlineSpan] {
        guard var queue = queues[key], !queue.isEmpty else { return [] }
        let spans = queue.removeFirst()
        queues[key] = queue
        return spans
    }

    private func key(for line: DiffTextLine) -> UnifiedLineKey {
        UnifiedLineKey(kind: line.kind, text: line.text, oldLine: line.oldLine, newLine: line.newLine)
    }

    private func buildBlocksLayout(_ diff: StructuredFileDiff) -> Layout {
        var oldLines: [PositionedLine] = []
        var newLines: [PositionedLine] = []
        var y: CGFloat = 0

        for hunk in diff.hunks {
            appendHunkHeader(hunk.header, oldY: y, newY: y, oldLines: &oldLines, newLines: &newLines)
            y += Self.lineHeight

            for segment in hunk.segments {
                switch segment.kind {
                case .context:
                    for line in segment.contextLines {
                        appendSideLine(line, oldY: y, newY: y, oldLines: &oldLines, newLines: &newLines)
                        y += Self.lineHeight
                    }
                case .change:
                    guard let change = segment.change else { continue }
                    let blockStart = y
                    for (index, pair) in change.linePairs.enumerated() {
                        let rowY = blockStart + CGFloat(index) * Self.lineHeight
                        if let oldLine = pair.oldLine {
                            oldLines.append(positioned(oldLine, side: .old, y: rowY))
                        }
                        if let newLine = pair.newLine {
                            newLines.append(positioned(newLine, side: .new, y: rowY))
                        }
                    }
                    y += CGFloat(max(change.linePairs.count, 1)) * Self.lineHeight
                }
            }
        }

        return Layout(
            contentHeight: y + Self.bottomPadding,
            syncMap: nil,
            oldLines: oldLines,
            newLines: newLines,
            unifiedLines: [],
            connectors: []
        )
    }

    private func buildFluidLayout(_ diff: StructuredFileDiff) -> Layout {
        let syncMap = FluidSyncMap.build(from: diff, lineHeight: Double(Self.lineHeight))
        var oldLines: [PositionedLine] = []
        var newLines: [PositionedLine] = []
        var connectors: [Connector] = []
        var oldY: CGFloat = 0
        var newY: CGFloat = 0

        for hunk in diff.hunks {
            appendHunkHeader(hunk.header, oldY: oldY, newY: newY, oldLines: &oldLines, newLines: &newLines)
            oldY += Self.lineHeight
            newY += Self.lineHeight

            for segment in hunk.segments {
                switch segment.kind {
                case .context:
                    for line in segment.contextLines {
                        appendSideLine(line, oldY: oldY, newY: newY, oldLines: &oldLines, newLines: &newLines)
                        oldY += Self.lineHeight
                        newY += Self.lineHeight
                    }
                case .change:
                    guard let change = segment.change else { continue }
                    let oldStart = oldY
                    let newStart = newY
                    for oldLine in change.oldLines {
                        oldLines.append(positioned(oldLine, side: .old, y: oldY))
                        oldY += Self.lineHeight
                    }
                    for newLine in change.newLines {
                        newLines.append(positioned(newLine, side: .new, y: newY))
                        newY += Self.lineHeight
                    }
                    connectors.append(Connector(
                        oldY: oldStart,
                        oldHeight: CGFloat(change.oldLines.count) * Self.lineHeight,
                        newY: newStart,
                        newHeight: CGFloat(change.newLines.count) * Self.lineHeight
                    ))
                }
            }
        }

        return Layout(
            contentHeight: CGFloat(syncMap.virtualHeight) + Self.bottomPadding,
            syncMap: syncMap,
            oldLines: oldLines,
            newLines: newLines,
            unifiedLines: [],
            connectors: connectors
        )
    }

    private func appendHunkHeader(
        _ header: String,
        oldY: CGFloat,
        newY: CGFloat,
        oldLines: inout [PositionedLine],
        newLines: inout [PositionedLine]
    ) {
        oldLines.append(PositionedLine(side: .old, y: oldY, text: header, oldLine: nil, newLine: nil, kind: .hunkHeader, inlineSpans: []))
        newLines.append(PositionedLine(side: .new, y: newY, text: header, oldLine: nil, newLine: nil, kind: .hunkHeader, inlineSpans: []))
    }

    private func appendSideLine(
        _ line: DiffTextLine,
        oldY: CGFloat,
        newY: CGFloat,
        oldLines: inout [PositionedLine],
        newLines: inout [PositionedLine]
    ) {
        oldLines.append(PositionedLine(side: .old, y: oldY, text: line.text, oldLine: line.oldLine, newLine: nil, kind: line.kind, inlineSpans: line.inlineSpans))
        newLines.append(PositionedLine(side: .new, y: newY, text: line.text, oldLine: nil, newLine: line.newLine, kind: line.kind, inlineSpans: line.inlineSpans))
    }

    private func positioned(_ line: DiffTextLine, side: Side, y: CGFloat) -> PositionedLine {
        PositionedLine(
            side: side,
            y: y,
            text: line.text,
            oldLine: side == .old ? line.oldLine : nil,
            newLine: side == .new ? line.newLine : nil,
            kind: line.kind,
            inlineSpans: line.inlineSpans
        )
    }

    private func drawUnified(_ visible: CGRect) {
        let textRect = bounds.insetBy(dx: Self.horizontalPadding, dy: 0)
        for line in renderLayout.unifiedLines where intersects(y: line.y, visible: visible) {
            drawUnifiedLine(line, rect: textRect, y: line.y)
        }
    }

    private func drawSplit(_ visible: CGRect, fluid: Bool) {
        let columns = columns(in: bounds)
        drawColumnChrome(columns, visible: visible)

        let offsets: FluidSyncMap.Offsets
        if fluid, let syncMap = renderLayout.syncMap {
            offsets = syncMap.offsets(for: Double(visible.minY))
        } else {
            offsets = .init(oldY: Double(visible.minY), newY: Double(visible.minY))
        }

        if fluid {
            drawConnectors(columns: columns, visible: visible, offsets: offsets)
        }

        drawSideLines(renderLayout.oldLines, side: .old, pane: columns.left, visible: visible, sideOffset: CGFloat(offsets.oldY))
        drawSideLines(renderLayout.newLines, side: .new, pane: columns.right, visible: visible, sideOffset: CGFloat(offsets.newY))
    }

    private func columns(in bounds: CGRect) -> Columns {
        let available = max(bounds.width - Self.horizontalPadding * 2 - Self.gutterWidth, 100)
        let paneWidth = floor(available / 2)
        let left = CGRect(x: Self.horizontalPadding, y: bounds.minY, width: paneWidth, height: bounds.height)
        let gutter = CGRect(x: left.maxX, y: bounds.minY, width: Self.gutterWidth, height: bounds.height)
        let right = CGRect(x: gutter.maxX, y: bounds.minY, width: paneWidth, height: bounds.height)
        return Columns(left: left, right: right, gutter: gutter)
    }

    private func drawColumnChrome(_ columns: Columns, visible: CGRect) {
        NSColor.separatorColor.withAlphaComponent(0.42).setFill()
        CGRect(x: columns.gutter.midX - 0.5, y: visible.minY, width: 1, height: visible.height).fill()
    }

    private func drawConnectors(columns: Columns, visible: CGRect, offsets: FluidSyncMap.Offsets) {
        for connector in renderLayout.connectors {
            let oldTop = visible.minY + connector.oldY - CGFloat(offsets.oldY)
            let oldBottom = oldTop + connector.oldHeight
            let newTop = visible.minY + connector.newY - CGFloat(offsets.newY)
            let newBottom = newTop + connector.newHeight
            let connectorRect = CGRect(
                x: columns.gutter.minX,
                y: min(oldTop, newTop) - Self.lineHeight,
                width: columns.gutter.width,
                height: abs(max(oldBottom, newBottom) - min(oldTop, newTop)) + Self.lineHeight * 2
            )
            guard connectorRect.intersects(visible) else { continue }

            let oldTopAnchor = connector.oldHeight == 0 ? oldTop + 1 : oldTop
            let oldBottomAnchor = connector.oldHeight == 0 ? oldTop + 2 : oldBottom
            let newTopAnchor = connector.newHeight == 0 ? newTop + 1 : newTop
            let newBottomAnchor = connector.newHeight == 0 ? newTop + 2 : newBottom
            let path = NSBezierPath()
            let leftX = columns.gutter.minX + 5
            let rightX = columns.gutter.maxX - 5
            let c1 = leftX + columns.gutter.width * 0.45
            let c2 = rightX - columns.gutter.width * 0.45

            path.move(to: NSPoint(x: leftX, y: oldTopAnchor))
            path.curve(to: NSPoint(x: rightX, y: newTopAnchor), controlPoint1: NSPoint(x: c1, y: oldTopAnchor), controlPoint2: NSPoint(x: c2, y: newTopAnchor))
            path.line(to: NSPoint(x: rightX, y: newBottomAnchor))
            path.curve(to: NSPoint(x: leftX, y: oldBottomAnchor), controlPoint1: NSPoint(x: c2, y: newBottomAnchor), controlPoint2: NSPoint(x: c1, y: oldBottomAnchor))
            path.close()

            connectorColor(connector).setFill()
            path.fill()
        }
    }

    private func drawSideLines(_ lines: [PositionedLine], side: Side, pane: CGRect, visible: CGRect, sideOffset: CGFloat) {
        let clipPath = NSBezierPath(rect: CGRect(x: pane.minX, y: visible.minY, width: pane.width, height: visible.height))
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        for line in lines {
            let y = visible.minY + line.y - sideOffset
            guard intersects(y: y, visible: visible) else { continue }
            drawSplitLine(line, pane: pane, y: y, side: side)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawUnifiedLine(_ line: PositionedLine, rect: CGRect, y: CGFloat) {
        let rowRect = CGRect(x: rect.minX, y: y, width: rect.width, height: Self.lineHeight)
        rowBackground(line.kind).setFill()
        rowRect.fill()

        drawLineNumber(line.oldLine, x: rowRect.minX, y: y)
        drawLineNumber(line.newLine, x: rowRect.minX + Self.lineNumberWidth, y: y)
        let marker = marker(for: line.kind)
        drawText(marker, x: rowRect.minX + Self.lineNumberWidth * 2 + 4, y: y, width: 16, color: markerColor(line.kind), font: lineNumberFont)
        drawText(
            line.text.isEmpty ? " " : line.text,
            x: rowRect.minX + Self.lineNumberWidth * 2 + 24,
            y: y,
            width: max(rowRect.width - Self.lineNumberWidth * 2 - 24, 20),
            color: textColor(line.kind),
            font: font,
            spans: line.inlineSpans
        )
    }

    private func drawSplitLine(_ line: PositionedLine, pane: CGRect, y: CGFloat, side: Side) {
        let rowRect = CGRect(x: pane.minX, y: y, width: pane.width, height: Self.lineHeight)
        rowBackground(line.kind).setFill()
        rowRect.fill()

        let number = side == .old ? line.oldLine : line.newLine
        drawLineNumber(number, x: rowRect.minX, y: y)
        drawText(
            line.text.isEmpty ? " " : line.text,
            x: rowRect.minX + Self.lineNumberWidth + Self.textLeftPadding,
            y: y,
            width: max(rowRect.width - Self.lineNumberWidth - Self.textLeftPadding, 20),
            color: textColor(line.kind),
            font: font,
            spans: line.inlineSpans
        )
    }

    private func drawLineNumber(_ number: Int?, x: CGFloat, y: CGFloat) {
        let text = number.map(String.init) ?? ""
        drawText(text, x: x, y: y, width: Self.lineNumberWidth - 8, color: NSColor.secondaryLabelColor, font: lineNumberFont, alignment: .right)
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
            attributed.addAttribute(.backgroundColor, value: inlineColor(span.kind), range: range)
        }
        attributed.draw(with: CGRect(x: x, y: y + 2, width: width, height: Self.lineHeight), options: [.usesLineFragmentOrigin])
    }

    private func nsRange(offset: Int, length: Int, in text: String) -> NSRange? {
        guard offset >= 0, length > 0,
              let start = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex),
              let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) else {
            return nil
        }
        return NSRange(start..<end, in: text)
    }

    private func intersects(y: CGFloat, visible: CGRect) -> Bool {
        y + Self.lineHeight >= visible.minY && y <= visible.maxY
    }

    private func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .hunkHeader: return "@"
        default: return " "
        }
    }

    private func markerColor(_ kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .addition: return NSColor.systemGreen
        case .deletion: return NSColor.systemRed
        case .hunkHeader: return NSColor.systemBlue
        default: return NSColor.secondaryLabelColor
        }
    }

    private func textColor(_ kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .fileHeader, .hunkHeader: return NSColor.secondaryLabelColor
        default: return NSColor.labelColor
        }
    }

    private func rowBackground(_ kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .addition: return NSColor.systemGreen.withAlphaComponent(0.12)
        case .deletion: return NSColor.systemRed.withAlphaComponent(0.12)
        case .hunkHeader: return NSColor.systemBlue.withAlphaComponent(0.08)
        default: return NSColor.clear
        }
    }

    private func inlineColor(_ kind: DiffInlineSpan.Kind) -> NSColor {
        switch kind {
        case .addition: return NSColor.systemGreen.withAlphaComponent(0.24)
        case .deletion: return NSColor.systemRed.withAlphaComponent(0.24)
        }
    }

    private func connectorColor(_ connector: Connector) -> NSColor {
        if connector.oldHeight == 0 {
            return NSColor.systemGreen.withAlphaComponent(0.14)
        }
        if connector.newHeight == 0 {
            return NSColor.systemRed.withAlphaComponent(0.14)
        }
        return NSColor.systemPurple.withAlphaComponent(0.15)
    }
}
