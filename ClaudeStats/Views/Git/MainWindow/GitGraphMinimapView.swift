import AppKit
import SwiftUI

struct GitGraphMinimapView: View {
    let data: GitGraphMinimapData
    let isLoading: Bool
    let onTargetMaxBucketsChange: (Int) -> Void
    let onSelectBucket: (GitGraphMinimapData.Bucket) -> Void
    @State private var hoveredBucketStart: Date?

    init(
        data: GitGraphMinimapData,
        isLoading: Bool,
        onTargetMaxBucketsChange: @escaping (Int) -> Void = { _ in },
        onSelectBucket: @escaping (GitGraphMinimapData.Bucket) -> Void
    ) {
        self.data = data
        self.isLoading = isLoading
        self.onTargetMaxBucketsChange = onTargetMaxBucketsChange
        self.onSelectBucket = onSelectBucket
    }

    private var totalCommits: Int {
        data.buckets.reduce(0) { $0 + $1.commitCount }
    }

    private var totalChurn: Int {
        data.buckets.reduce(0) { $0 + $1.churn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("HISTORY")
                    .font(.sora(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("\(totalCommits) commits")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                Text("\(Format.tokens(totalChurn)) churn")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            GeometryReader { proxy in
                let targetMaxBuckets = Self.targetMaxBuckets(for: proxy.size.width)
                ZStack {
                    Canvas { context, size in
                        draw(context: &context, size: size)
                    }
                    .allowsHitTesting(false)

                    GitGraphMinimapInteractionLayer { location in
                        if let location {
                            updateHoverBucket(at: location.x, size: proxy.size)
                        } else if hoveredBucketStart != nil {
                            hoveredBucketStart = nil
                        }
                    } onClick: { location in
                        if let bucket = bucket(at: location.x, size: proxy.size) {
                            onSelectBucket(bucket)
                        }
                    }
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .task(id: targetMaxBuckets) {
                    onTargetMaxBucketsChange(targetMaxBuckets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppSurface.panelFill)
    }

    nonisolated static func targetMaxBuckets(for width: CGFloat) -> Int {
        if width < 420 { return 80 }
        if width < 760 { return 120 }
        return 160
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard !data.buckets.isEmpty, size.width > 1, size.height > 1 else { return }
        let layout = GitGraphMinimapPlotLayout(size: size)
        guard layout.plotWidth > 1 else { return }

        drawGrid(context: &context, rect: layout.densityRect)
        drawDensity(context: &context, layout: layout)
        drawChurn(context: &context, layout: layout)
        drawMarkers(context: &context, layout: layout)
        drawHoverIndicator(context: &context, layout: layout)
        drawSelection(context: &context, layout: layout)
    }

    private func drawGrid(context: inout GraphicsContext, rect: CGRect) {
        for offset in [CGFloat(0), rect.height / 2, rect.height] {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
            context.stroke(path, with: .color(Color.stxStroke.opacity(0.8)), lineWidth: 1)
        }
    }

    private func drawDensity(context: inout GraphicsContext, layout: GitGraphMinimapPlotLayout) {
        let rect = layout.densityRect
        let points = data.buckets.enumerated().map { index, bucket in
            point(index: index, value: bucket.commitCount, maxValue: data.maxCommitCount, rect: rect, layout: layout)
        }
        guard let first = points.first, let last = points.last else { return }

        var line = Path()
        appendMonotoneCurve(points, to: &line)

        var area = Path()
        area.move(to: CGPoint(x: first.x, y: rect.maxY))
        appendMonotoneCurve(points, to: &area, moveToFirst: false)
        area.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        area.closeSubpath()

        context.fill(area, with: .color(Color.stxAccent.opacity(0.15)))
        context.stroke(line, with: .color(Color.stxAccent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
    }

    private func drawChurn(context: inout GraphicsContext, layout: GitGraphMinimapPlotLayout) {
        let rect = layout.churnRect
        let count = data.buckets.count
        guard count > 0 else { return }
        let slotWidth = count <= 1 ? rect.width : rect.width / CGFloat(count - 1)
        let barWidth = max(1, min(10, slotWidth * 0.45))
        for (index, bucket) in data.buckets.enumerated() where bucket.churn > 0 {
            let normalized = CGFloat(bucket.churn) / CGFloat(max(data.maxChurn, 1))
            let height = max(1, rect.height * min(max(normalized, 0), 1))
            let centerX = layout.clampedX(layout.xPosition(index: index, count: count), radius: barWidth / 2)
            let barRect = CGRect(x: centerX - barWidth / 2, y: rect.maxY - height, width: barWidth, height: height)
            var path = Path()
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(GitPalette.add.opacity(0.65)))
        }
    }

    private func drawMarkers(context: inout GraphicsContext, layout: GitGraphMinimapPlotLayout) {
        let starts = Dictionary(uniqueKeysWithValues: data.buckets.enumerated().map { ($0.element.start, $0.offset) })
        var drawn: Set<String> = []
        for marker in data.markers {
            guard let index = starts[marker.bucketStart] else { continue }
            let rect = layout.markerRect(index: index, count: data.buckets.count, marker: marker)
            let color = markerColor(marker)
            guard drawn.insert("\(Int(rect.midX))|\(Int(rect.minY))|\(marker.priority)|\(marker.kind)").inserted else { continue }
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(color))
        }
    }

    private func drawHoverIndicator(context: inout GraphicsContext, layout: GitGraphMinimapPlotLayout) {
        guard let hovered = hoveredBucketStart,
              let index = data.buckets.firstIndex(where: { $0.start == hovered }) else { return }
        let x = layout.xPosition(index: index, count: data.buckets.count)
        var path = Path()
        path.move(to: CGPoint(x: x, y: layout.selectionLineStartY))
        path.addLine(to: CGPoint(x: x, y: layout.selectionLineEndY))
        context.stroke(path, with: .color(Color.stxAccent.opacity(0.42)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        context.fill(Path(ellipseIn: layout.hoverDotRect(index: index, count: data.buckets.count)), with: .color(Color.stxAccent.opacity(0.62)))
    }

    private func drawSelection(context: inout GraphicsContext, layout: GitGraphMinimapPlotLayout) {
        guard let selected = data.selectedBucketStart,
              let index = data.buckets.firstIndex(where: { $0.start == selected }) else { return }
        let x = layout.xPosition(index: index, count: data.buckets.count)
        var path = Path()
        path.move(to: CGPoint(x: x, y: layout.selectionLineStartY))
        path.addLine(to: CGPoint(x: x, y: layout.selectionLineEndY))
        context.stroke(path, with: .color(Color.stxAccent.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        context.fill(Path(ellipseIn: layout.selectedDotRect(index: index, count: data.buckets.count)), with: .color(Color.stxAccent))
    }

    private func markerColor(_ marker: GitGraphMinimapData.Marker) -> Color {
        switch marker.kind {
        case .head:
            return GitPalette.head
        case .branch:
            return marker.priority == .primary ? Color.primary.opacity(0.85) : Color.primary.opacity(0.48)
        case .remoteBranch:
            return Color.stxMuted.opacity(marker.priority == .secondary ? 0.58 : 1)
        case .tag:
            return GitPalette.tag.opacity(marker.priority == .secondary ? 0.62 : 1)
        case .workingTree:
            return GitPalette.add
        }
    }

    private func point(index: Int, value: Int, maxValue: Int, rect: CGRect, layout: GitGraphMinimapPlotLayout) -> CGPoint {
        let x = layout.xPosition(index: index, count: data.buckets.count)
        let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
        let y = rect.maxY - rect.height * min(max(normalized, 0), 1)
        return CGPoint(x: x, y: y)
    }

    private func bucket(at x: CGFloat, size: CGSize) -> GitGraphMinimapData.Bucket? {
        guard let index = GitGraphMinimapPlotLayout(size: size)
            .bucketIndex(at: x, count: data.buckets.count) else { return nil }
        return data.buckets[min(max(index, 0), data.buckets.count - 1)]
    }

    private func updateHoverBucket(at x: CGFloat, size: CGSize) {
        let nextBucketStart = bucket(at: x, size: size)?.start
        if hoveredBucketStart != nextBucketStart {
            hoveredBucketStart = nextBucketStart
        }
    }

    private func appendMonotoneCurve(_ points: [CGPoint], to path: inout Path, moveToFirst: Bool = true) {
        guard let first = points.first else { return }
        if moveToFirst {
            path.move(to: first)
        } else {
            path.addLine(to: first)
        }
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return
        }

        let tangents = monotoneTangents(for: points)
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let dx = next.x - current.x
            path.addCurve(
                to: next,
                control1: CGPoint(x: current.x + dx / 3, y: current.y + tangents[index] * dx / 3),
                control2: CGPoint(x: next.x - dx / 3, y: next.y - tangents[index + 1] * dx / 3)
            )
        }
    }

    private func monotoneTangents(for points: [CGPoint]) -> [CGFloat] {
        let count = points.count
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let slopes = (0..<(count - 1)).map { index -> CGFloat in
            let dx = points[index + 1].x - points[index].x
            guard abs(dx) > CGFloat.ulpOfOne else { return 0 }
            return (points[index + 1].y - points[index].y) / dx
        }
        var tangents = Array(repeating: CGFloat(0), count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        if count > 2 {
            for index in 1..<(count - 1) {
                let previous = slopes[index - 1]
                let next = slopes[index]
                tangents[index] = previous * next <= 0 ? 0 : (previous + next) / 2
            }
        }
        for index in 0..<(count - 1) {
            let slope = slopes[index]
            if abs(slope) <= CGFloat.ulpOfOne {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let a = tangents[index] / slope
            let b = tangents[index + 1] / slope
            let magnitude = sqrt(a * a + b * b)
            if magnitude > 3 {
                let scale = 3 / magnitude
                tangents[index] = scale * a * slope
                tangents[index + 1] = scale * b * slope
            }
        }
        return tangents
    }
}

private struct GitGraphMinimapInteractionLayer: NSViewRepresentable {
    var onHover: (CGPoint?) -> Void
    var onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHover = onHover
        nsView.onClick = onClick
        nsView.refreshHoverFromCurrentMouseLocation()
    }

    @MainActor
    final class TrackingView: NSView {
        var onHover: (CGPoint?) -> Void = { _ in }
        var onClick: (CGPoint) -> Void = { _ in }

        private var trackingArea: NSTrackingArea?
        private var localMouseMovedMonitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureMouseMovedEvents()
            installLocalMouseMovedMonitor()
            refreshHoverFromCurrentMouseLocation()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                removeLocalMouseMovedMonitor()
                onHover(nil)
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
            refreshHoverFromCurrentMouseLocation()
        }

        override func mouseEntered(with event: NSEvent) {
            sendHover(for: event)
        }

        override func mouseMoved(with event: NSEvent) {
            sendHover(for: event)
        }

        override func mouseExited(with event: NSEvent) {
            onHover(nil)
        }

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return }
            onClick(location)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func refreshHoverFromCurrentMouseLocation() {
            guard let window else { return }
            let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            onHover(bounds.contains(location) ? location : nil)
        }

        private func configureMouseMovedEvents() {
            window?.acceptsMouseMovedEvents = true
        }

        private func installLocalMouseMovedMonitor() {
            removeLocalMouseMovedMonitor()
            localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window else { return }
                    self.sendHover(for: event)
                }
                return event
            }
        }

        private func removeLocalMouseMovedMonitor() {
            if let localMouseMovedMonitor {
                NSEvent.removeMonitor(localMouseMovedMonitor)
                self.localMouseMovedMonitor = nil
            }
        }

        private func sendHover(for event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onHover(bounds.contains(location) ? location : nil)
        }
    }
}

struct GitGraphMinimapPlotLayout {
    static let horizontalInset: CGFloat = 4
    static let verticalInset: CGFloat = 1
    static let selectedDotRadius: CGFloat = 3
    static let hoverDotRadius: CGFloat = 2.5

    let size: CGSize

    var plotWidth: CGFloat {
        max(0, size.width - Self.horizontalInset * 2)
    }

    var densityRect: CGRect {
        CGRect(
            x: Self.horizontalInset,
            y: Self.verticalInset,
            width: plotWidth,
            height: min(29, max(1, size.height - 19))
        )
    }

    var churnRect: CGRect {
        let y = min(max(densityRect.maxY + 5, Self.verticalInset), max(Self.verticalInset, size.height - 2))
        return CGRect(
            x: Self.horizontalInset,
            y: y,
            width: plotWidth,
            height: max(1, size.height - y - Self.verticalInset)
        )
    }

    var selectionLineStartY: CGFloat {
        Self.verticalInset
    }

    var selectionLineEndY: CGFloat {
        max(selectionLineStartY, size.height - Self.verticalInset)
    }

    func xPosition(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return size.width / 2 }
        let ratio = CGFloat(min(max(index, 0), count - 1)) / CGFloat(count - 1)
        return Self.horizontalInset + plotWidth * ratio
    }

    func bucketIndex(at x: CGFloat, count: Int) -> Int? {
        guard count > 0, size.width > 0 else { return nil }
        guard count > 1, plotWidth > 0 else { return 0 }
        let clamped = min(max(x, Self.horizontalInset), Self.horizontalInset + plotWidth)
        let ratio = (clamped - Self.horizontalInset) / plotWidth
        return min(max(Int((ratio * CGFloat(count - 1)).rounded()), 0), count - 1)
    }

    func selectedDotRect(index: Int, count: Int) -> CGRect {
        indicatorDotRect(index: index, count: count, radius: Self.selectedDotRadius)
    }

    func hoverDotRect(index: Int, count: Int) -> CGRect {
        indicatorDotRect(index: index, count: count, radius: Self.hoverDotRadius)
    }

    private func indicatorDotRect(index: Int, count: Int, radius: CGFloat) -> CGRect {
        let centerX = clampedX(xPosition(index: index, count: count), radius: radius)
        let centerY = min(max(densityRect.maxY, radius), max(radius, size.height - radius))
        return CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
    }

    func markerRect(index: Int, count: Int, marker: GitGraphMinimapData.Marker) -> CGRect {
        let width: CGFloat = marker.priority == .primary ? 3 : 2
        let centerX = clampedX(xPosition(index: index, count: count), radius: width / 2)
        if marker.kind == .workingTree {
            return CGRect(
                x: centerX - width / 2,
                y: Self.verticalInset,
                width: width,
                height: max(1, size.height - Self.verticalInset * 2)
            )
        }
        let height: CGFloat = marker.priority == .primary ? 8 : 6
        let y = max(Self.verticalInset, size.height - Self.verticalInset - height)
        return CGRect(x: centerX - width / 2, y: y, width: width, height: height)
    }

    func clampedX(_ x: CGFloat, radius: CGFloat) -> CGFloat {
        min(max(x, radius), max(radius, size.width - radius))
    }
}
