import SwiftUI

struct GitGraphMinimapView: View {
    let data: GitGraphMinimapData
    let isLoading: Bool
    let onSelectBucket: (GitGraphMinimapData.Bucket) -> Void

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
                Canvas { context, size in
                    draw(context: &context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if let bucket = bucket(at: value.location.x, width: proxy.size.width) {
                                onSelectBucket(bucket)
                            }
                        }
                )
            }
            .frame(height: 48)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025))
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard !data.buckets.isEmpty, size.width > 1, size.height > 1 else { return }
        let densityRect = CGRect(x: 0, y: 0, width: size.width, height: 30)
        let churnRect = CGRect(x: 0, y: 34, width: size.width, height: 14)

        drawGrid(context: &context, rect: densityRect)
        drawDensity(context: &context, rect: densityRect)
        drawChurn(context: &context, rect: churnRect)
        drawMarkers(context: &context, size: size)
        drawSelection(context: &context, size: size)
    }

    private func drawGrid(context: inout GraphicsContext, rect: CGRect) {
        for offset in [CGFloat(0), rect.height / 2, rect.height] {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
            context.stroke(path, with: .color(Color.stxStroke.opacity(0.8)), lineWidth: 1)
        }
    }

    private func drawDensity(context: inout GraphicsContext, rect: CGRect) {
        let points = data.buckets.enumerated().map { index, bucket in
            point(index: index, value: bucket.commitCount, maxValue: data.maxCommitCount, rect: rect)
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

    private func drawChurn(context: inout GraphicsContext, rect: CGRect) {
        let count = data.buckets.count
        guard count > 0 else { return }
        let slotWidth = rect.width / CGFloat(count)
        let barWidth = max(1, min(10, slotWidth * 0.55))
        for (index, bucket) in data.buckets.enumerated() where bucket.churn > 0 {
            let normalized = CGFloat(bucket.churn) / CGFloat(max(data.maxChurn, 1))
            let height = max(1, rect.height * min(max(normalized, 0), 1))
            let x = rect.minX + CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2
            let barRect = CGRect(x: x, y: rect.maxY - height, width: barWidth, height: height)
            var path = Path()
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(GitPalette.add.opacity(0.65)))
        }
    }

    private func drawMarkers(context: inout GraphicsContext, size: CGSize) {
        let starts = Dictionary(uniqueKeysWithValues: data.buckets.enumerated().map { ($0.element.start, $0.offset) })
        var drawn: Set<String> = []
        for marker in data.markers {
            guard let index = starts[marker.bucketStart] else { continue }
            let x = xPosition(index: index, width: size.width)
            let color = markerColor(marker.kind)
            let y = marker.kind == .workingTree ? CGFloat(0) : CGFloat(39)
            let rect = CGRect(x: x - 1.5, y: y, width: 3, height: marker.kind == .workingTree ? size.height : 7)
            guard drawn.insert("\(Int(x))|\(Int(y))|\(marker.kind)").inserted else { continue }
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            context.fill(path, with: .color(color))
        }
    }

    private func drawSelection(context: inout GraphicsContext, size: CGSize) {
        guard let selected = data.selectedBucketStart,
              let index = data.buckets.firstIndex(where: { $0.start == selected }) else { return }
        let x = xPosition(index: index, width: size.width)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(Color.stxAccent.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        let dot = CGRect(x: x - 3, y: 27, width: 6, height: 6)
        context.fill(Path(ellipseIn: dot), with: .color(Color.stxAccent))
    }

    private func markerColor(_ kind: GitGraphMinimapData.Marker.Kind) -> Color {
        switch kind {
        case .head: return GitPalette.head
        case .branch: return Color.primary.opacity(0.55)
        case .remoteBranch: return Color.stxMuted
        case .tag: return GitPalette.tag
        case .workingTree: return GitPalette.add
        }
    }

    private func point(index: Int, value: Int, maxValue: Int, rect: CGRect) -> CGPoint {
        let x = xPosition(index: index, width: rect.width) + rect.minX
        let normalized = CGFloat(value) / CGFloat(max(maxValue, 1))
        let y = rect.maxY - rect.height * min(max(normalized, 0), 1)
        return CGPoint(x: x, y: y)
    }

    private func xPosition(index: Int, width: CGFloat) -> CGFloat {
        data.buckets.count <= 1 ? width / 2 : width * CGFloat(index) / CGFloat(data.buckets.count - 1)
    }

    private func bucket(at x: CGFloat, width: CGFloat) -> GitGraphMinimapData.Bucket? {
        guard !data.buckets.isEmpty, width > 0 else { return nil }
        if data.buckets.count == 1 { return data.buckets[0] }
        let ratio = min(max(x / width, 0), 1)
        let index = Int((ratio * CGFloat(data.buckets.count - 1)).rounded())
        return data.buckets[min(max(index, 0), data.buckets.count - 1)]
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
