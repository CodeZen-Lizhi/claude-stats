import Charts
import SwiftUI

private enum SemanticVisualizationMode: String, CaseIterable, Identifiable {
    case atlas
    case bubbles
    case cloud
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atlas: "Atlas"
        case .bubbles: "Bubbles"
        case .cloud: "Cloud"
        case .timeline: "Timeline"
        }
    }

    var symbol: String {
        switch self {
        case .atlas: "point.3.connected.trianglepath.dotted"
        case .bubbles: "circle.grid.3x3.circle"
        case .cloud: "textformat"
        case .timeline: "chart.xyaxis.line"
        }
    }
}

struct SemanticVisualizationShowcase: View {
    let analysis: TranscriptAnalysisSnapshot
    let sessions: [Session]

    @State private var mode: SemanticVisualizationMode = .atlas
    @State private var selectedTermID: String?
    @State private var hoveredTermID: String?
    @State private var visualization: SemanticVisualizationSnapshot?
    @State private var cacheKey: String?

    private var currentCacheKey: String {
        let latestSessionDate = sessions
            .map { ($0.stats?.lastActivity ?? $0.lastModified).timeIntervalSinceReferenceDate }
            .max() ?? 0
        return [
            analysis.provider.rawValue,
            String(Int(analysis.generatedAt.timeIntervalSinceReferenceDate.rounded())),
            String(analysis.terms.count),
            String(analysis.sessionAnalyses.count),
            String(sessions.count),
            String(Int(latestSessionDate.rounded())),
            analysis.dictionarySignature,
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Group {
                if let visualization, !visualization.isEmpty {
                    chartStage(visualization)
                } else {
                    placeholder
                }
            }
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.stxStroke.opacity(0.75), lineWidth: 1))

            if let visualization {
                SemanticSelectionSummary(
                    visualization: visualization,
                    selectedTermID: selectedTermID,
                    hoveredTermID: hoveredTermID
                )
            }
        }
        .appSurface(.mainWindowCard, padding: 16)
        .onAppear { rebuildIfNeeded() }
        .onChange(of: currentCacheKey) { _, _ in rebuildIfNeeded() }
        .onChange(of: mode) { _, _ in
            hoveredTermID = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SEMANTIC MAP")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)
                Text("Global structure across extracted terms and sessions.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 12)

            Picker("Visualization", selection: $mode) {
                ForEach(SemanticVisualizationMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
        }
    }

    @ViewBuilder
    private func chartStage(_ visualization: SemanticVisualizationSnapshot) -> some View {
        switch mode {
        case .atlas:
            SemanticAtlasView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        case .bubbles:
            SemanticBubbleAtlasView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        case .cloud:
            SemanticWordCloudView(
                visualization: visualization,
                selectedTermID: $selectedTermID,
                hoveredTermID: $hoveredTermID
            )
        case .timeline:
            SemanticTimelineBubbleChart(
                visualization: visualization,
                selectedTermID: $selectedTermID
            )
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.stxMuted.opacity(0.65))
            Text("No semantic terms to visualize yet.")
                .font(.sora(12, weight: .medium))
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func rebuildIfNeeded() {
        let key = currentCacheKey
        guard cacheKey != key else { return }
        visualization = SemanticVisualizationSnapshot(analysis: analysis, sessions: sessions)
        cacheKey = key
        selectedTermID = nil
        hoveredTermID = nil
    }
}

private struct SemanticSelectionSummary: View {
    let visualization: SemanticVisualizationSnapshot
    let selectedTermID: String?
    let hoveredTermID: String?

    private var activeNode: SemanticTermNode? {
        visualization.node(for: selectedTermID) ?? visualization.node(for: hoveredTermID)
    }

    var body: some View {
        if let activeNode {
            termSummary(activeNode)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                Text("Select or hover a term to inspect frequency, score, and examples.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private func termSummary(_ node: SemanticTermNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(node.displayName, systemImage: node.kind.symbol)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(node.kind.displayName)
                    .font(.sora(9, weight: .medium))
                    .foregroundStyle(SemanticVisualizationPalette.color(for: node.kind))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SemanticVisualizationPalette.color(for: node.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                Spacer(minLength: 0)
                Text("freq \(node.frequency) - sessions \(node.documentFrequency) - score \(String(format: "%.1f", node.tfidf))")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            if !node.examples.isEmpty {
                ForEach(Array(node.examples.prefix(2))) { example in
                    HStack(alignment: .top, spacing: 8) {
                        Text(example.sessionTitle)
                            .font(.sora(10, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        Text(example.excerpt)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SemanticAtlasView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    private var activeID: String? { hoveredTermID ?? selectedTermID }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SemanticNetworkEdgesCanvas(
                    visualization: visualization,
                    positionedNodes: visualization.atlasNodes,
                    activeTermID: activeID
                )
                ForEach(visualization.atlasNodes) { positioned in
                    if let node = visualization.node(for: positioned.nodeID) {
                        SemanticNodeButton(
                            node: node,
                            positioned: positioned,
                            canvasSize: geometry.size,
                            selected: selectedTermID == node.id,
                            highlighted: isHighlighted(node.id),
                            alwaysShowsLabel: node.score > 0.78
                        ) {
                            selectedTermID = selectedTermID == node.id ? nil : node.id
                        } hover: { hovering in
                            hoveredTermID = hovering ? node.id : nil
                        }
                    }
                }
            }
            .padding(14)
            .background(SemanticVisualizationBackground())
        }
    }

    private func isHighlighted(_ nodeID: String) -> Bool {
        guard let activeID else { return false }
        if activeID == nodeID { return true }
        return visualization.edges.contains { edge in
            (edge.sourceID == activeID && edge.targetID == nodeID) || (edge.targetID == activeID && edge.sourceID == nodeID)
        }
    }
}

private struct SemanticBubbleAtlasView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SemanticVisualizationBackground()
                bubbleGroupLabels(size: geometry.size)

                ForEach(visualization.bubbleNodes) { positioned in
                    if let node = visualization.node(for: positioned.nodeID) {
                        SemanticNodeButton(
                            node: node,
                            positioned: positioned,
                            canvasSize: geometry.size,
                            selected: selectedTermID == node.id,
                            highlighted: hoveredTermID == node.id,
                            alwaysShowsLabel: node.score > 0.62
                        ) {
                            selectedTermID = selectedTermID == node.id ? nil : node.id
                        } hover: { hovering in
                            hoveredTermID = hovering ? node.id : nil
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func bubbleGroupLabels(size: CGSize) -> some View {
        let groups = Dictionary(grouping: visualization.bubbleNodes, by: { visualization.node(for: $0.nodeID)?.kind ?? .general })
        return ZStack {
            ForEach(TranscriptTermKind.allCases, id: \.self) { kind in
                if let matching = groups[kind], let positioned = matching.first {
                    let x = matching.map(\.x).reduce(0, +) / Double(max(matching.count, 1))
                    let y = max(0.05, (matching.map(\.y).min() ?? positioned.y) - 0.05)
                    Text(kind.displayName.uppercased())
                        .font(.sora(9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(SemanticVisualizationPalette.color(for: kind).opacity(0.82))
                        .position(x: x * size.width, y: y * size.height)
                }
            }
        }
    }
}

private struct SemanticWordCloudView: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?
    @Binding var hoveredTermID: String?

    var body: some View {
        ZStack {
            SemanticVisualizationBackground()
            SemanticWordCloudFlowLayout(spacing: 10, rowSpacing: 10) {
                ForEach(visualization.wordCloudItems) { item in
                    Button {
                        selectedTermID = selectedTermID == item.nodeID ? nil : item.nodeID
                    } label: {
                        Text(item.text)
                            .font(.sora(item.fontSize, weight: selectedTermID == item.nodeID ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(SemanticVisualizationPalette.color(for: item.kind).opacity(hoveredTermID == item.nodeID || selectedTermID == item.nodeID ? 1 : 0.78))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background {
                                if selectedTermID == item.nodeID {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(SemanticVisualizationPalette.color(for: item.kind).opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(visualization.node(for: item.nodeID)?.helpText ?? item.text)
                    .onHover { hovering in hoveredTermID = hovering ? item.nodeID : nil }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct SemanticTimelineBubbleChart: View {
    let visualization: SemanticVisualizationSnapshot
    @Binding var selectedTermID: String?

    var body: some View {
        ZStack {
            SemanticVisualizationBackground()
            if visualization.timelinePoints.isEmpty {
                Text("No dated semantic activity to chart.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            } else {
                chart
                    .padding(16)
            }
        }
    }

    private var chart: some View {
        let unit: Calendar.Component = {
            switch visualization.timelineGranularity {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }()

        return Chart(visualization.timelinePoints) { point in
            PointMark(
                x: .value(visualization.timelineGranularity.displayName, point.date, unit: unit),
                y: .value("Kind", point.kind.displayName)
            )
            .foregroundStyle(by: .value("Kind", point.kind.displayName))
            .symbolSize(CGFloat(80 + point.score * 1_320))
            .opacity(0.78)
            .annotation(position: .top, alignment: .center) {
                if point.score > 0.74, let node = visualization.node(for: point.topTermID) {
                    Text(node.displayName)
                        .font(.sora(8, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel("\(point.kind.displayName), \(Format.day(point.date))")
            .accessibilityValue(String(format: "%.1f", point.value))
        }
        .chartForegroundStyleScale(
            domain: TranscriptTermKind.allCases.map(\.displayName),
            range: TranscriptTermKind.allCases.map(SemanticVisualizationPalette.color(for:))
        )
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.stxStroke.opacity(0.8))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Format.day(date))
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.stxStroke.opacity(0.55))
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.sora(9, weight: .medium))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .overlay(alignment: .topTrailing) {
            SemanticSizeLegend()
                .padding(8)
        }
    }
}

private struct SemanticSizeLegend: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach([10.0, 15.0, 22.0], id: \.self) { size in
                Circle()
                    .strokeBorder(Color.stxMuted.opacity(0.55), lineWidth: 1)
                    .frame(width: size, height: size)
            }
            Text("importance")
                .font(.sora(8))
                .foregroundStyle(Color.stxMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.stxBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SemanticNetworkEdgesCanvas: View {
    let visualization: SemanticVisualizationSnapshot
    let positionedNodes: [SemanticPositionedNode]
    let activeTermID: String?

    var body: some View {
        Canvas { context, size in
            let positions = Dictionary(uniqueKeysWithValues: positionedNodes.map { ($0.nodeID, $0) })
            for edge in visualization.edges {
                guard let sourcePosition = positions[edge.sourceID],
                      let targetPosition = positions[edge.targetID],
                      let sourceNode = visualization.node(for: edge.sourceID) else {
                    continue
                }
                let source = CGPoint(x: sourcePosition.x * size.width, y: sourcePosition.y * size.height)
                let target = CGPoint(x: targetPosition.x * size.width, y: targetPosition.y * size.height)
                var path = Path()
                path.move(to: source)
                path.addLine(to: target)
                let connected = activeTermID == nil || activeTermID == edge.sourceID || activeTermID == edge.targetID
                let opacity = connected ? 0.12 + edge.strength * 0.33 : 0.045
                context.stroke(
                    path,
                    with: .color(SemanticVisualizationPalette.color(for: sourceNode.kind).opacity(opacity)),
                    lineWidth: connected ? 0.7 + edge.strength * 1.4 : 0.5
                )
            }
        }
    }
}

private struct SemanticNodeButton: View {
    let node: SemanticTermNode
    let positioned: SemanticPositionedNode
    let canvasSize: CGSize
    let selected: Bool
    let highlighted: Bool
    let alwaysShowsLabel: Bool
    let action: () -> Void
    let hover: (Bool) -> Void

    private var diameter: CGFloat {
        max(10, min(canvasSize.width, canvasSize.height) * CGFloat(positioned.radius) * 2)
    }

    var body: some View {
        ZStack {
            Button(action: action) {
                Circle()
                    .fill(SemanticVisualizationPalette.color(for: node.kind).opacity(highlighted || selected ? 0.92 : 0.66))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(selected ? 0.95 : highlighted ? 0.62 : 0.28), lineWidth: selected ? 2 : 1)
                    }
                    .shadow(color: SemanticVisualizationPalette.color(for: node.kind).opacity(selected ? 0.36 : highlighted ? 0.22 : 0.12), radius: selected ? 10 : 5, y: 2)
            }
            .buttonStyle(.plain)
            .frame(width: diameter, height: diameter)
            .help(node.helpText)
            .accessibilityLabel(node.displayName)
            .accessibilityValue("\(node.kind.displayName), frequency \(node.frequency), sessions \(node.documentFrequency)")
            .onHover(perform: hover)

            if alwaysShowsLabel || selected || highlighted {
                Text(node.displayName)
                    .font(.sora(selected ? 10 : 9, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.stxBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(y: diameter / 2 + 9)
                    .allowsHitTesting(false)
            }
        }
        .position(x: positioned.x * canvasSize.width, y: positioned.y * canvasSize.height)
        .zIndex(selected ? 10 : highlighted ? 8 : alwaysShowsLabel ? 4 : 1)
    }
}

private struct SemanticVisualizationBackground: View {
    var body: some View {
        ZStack {
            Color.primary.opacity(0.032)
            Canvas { context, size in
                let step: CGFloat = 36
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(Color.stxStroke.opacity(0.34)), lineWidth: 0.5)
            }
        }
    }
}

private struct SemanticWordCloudFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        var y = bounds.midY - totalHeight / 2
        for row in rows {
            var x = bounds.midX - row.width / 2
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > width, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.append(FlowItem(subview: subview, size: size), spacing: spacing)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ item: FlowItem, spacing: CGFloat) {
            if !items.isEmpty { width += spacing }
            items.append(item)
            width += item.size.width
            height = max(height, item.size.height)
        }
    }
}

private enum SemanticVisualizationPalette {
    static func color(for kind: TranscriptTermKind) -> Color {
        switch kind {
        case .language: Color(red: 0.20, green: 0.63, blue: 0.86)
        case .framework: Color(red: 0.96, green: 0.44, blue: 0.13)
        case .api: Color(red: 0.58, green: 0.42, blue: 0.92)
        case .typeName: Color(red: 0.22, green: 0.48, blue: 0.90)
        case .function: Color(red: 0.20, green: 0.68, blue: 0.42)
        case .filePath: Color(red: 0.18, green: 0.62, blue: 0.58)
        case .command: Color(red: 0.93, green: 0.66, blue: 0.12)
        case .configKey: Color(red: 0.86, green: 0.38, blue: 0.68)
        case .error: Color(red: 0.91, green: 0.21, blue: 0.13)
        case .workflow: Color(red: 0.48, green: 0.72, blue: 0.24)
        case .general: Color.stxMuted
        }
    }
}

private extension SemanticTermNode {
    var helpText: String {
        "\(displayName) - \(kind.displayName) - freq \(frequency) - sessions \(documentFrequency) - score \(String(format: "%.1f", tfidf))"
    }
}
