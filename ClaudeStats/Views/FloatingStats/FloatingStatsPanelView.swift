import SwiftUI

struct FloatingStatsPanelView: View {
    @Environment(AppEnvironment.self) private var env

    let state: FloatingStatsPanelState
    var onHoverChanged: (Bool) -> Void
    var onDragBegan: (CGPoint) -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    var body: some View {
        let edge = state.edge
        let shape = FloatingTabShape(
            edge: edge,
            cornerRadius: state.isExpanded ? 18 : 24,
            edgeReleaseProgress: state.edgeReleaseProgress
        )
        let size = FloatingPanelGeometry.size(edge: edge, expanded: state.isExpanded)

        ZStack {
            if state.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                collapsedContent(edge: edge, size: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            shape.fill(.regularMaterial)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.stxStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .overlay(FloatingHoverTracker(onHoverChanged: onHoverChanged).accessibilityHidden(true))
        .font(.sora(13))
        .tint(.stxAccent)
        .animation(.easeOut(duration: 0.16), value: state.isExpanded)
        .animation(.easeOut(duration: 0.16), value: state.edge)
        .animation(.easeOut(duration: 0.14), value: state.edgeReleaseProgress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude Stats floating tab")
    }

    private func collapsedContent(edge: FloatingPanelEdge, size: CGSize) -> some View {
        let title = env.preferences.selectedProvider.shortName.lowercased()
        return Group {
            if edge.isVertical {
                sideCollapsedTitle(title, edge: edge, size: size)
            } else {
                horizontalCollapsedTitle(title)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.collapsedContentPadding)
            .overlay(dragHandle)
            .accessibilityHint("Hover to expand. Drag to snap to another screen edge.")
    }

    private func horizontalCollapsedTitle(_ title: String) -> some View {
        Text(title)
            .font(.sora(13, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func sideCollapsedTitle(_ title: String, edge: FloatingPanelEdge, size: CGSize) -> some View {
        let innerSize = CGSize(
            width: max(size.width - Metrics.collapsedContentPadding * 2, 1),
            height: max(size.height - Metrics.collapsedContentPadding * 2, 1)
        )

        return sideCollapsedTitleText(title)
            .frame(width: innerSize.height, height: innerSize.width)
            .rotationEffect(sideTitleRotation(for: edge))
            .frame(width: innerSize.width, height: innerSize.height)
            .accessibilityLabel(title)
    }

    private func sideCollapsedTitleText(_ title: String) -> some View {
        Text(title)
            .font(.sora(14, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func sideTitleRotation(for edge: FloatingPanelEdge) -> Angle {
        switch edge {
        case .right: .degrees(-90)
        case .left: .degrees(90)
        case .top, .bottom: .zero
        }
    }

    private var expandedContent: some View {
        let prefs = env.preferences
        let provider = prefs.selectedProvider
        let summary = env.store.summary(for: prefs.menuBarPeriod, provider: provider)

        return VStack(alignment: .leading, spacing: 10) {
            header(provider: provider, period: prefs.menuBarPeriod)
                .overlay(dragHandle)

            StxRule()

            HStack(alignment: .top, spacing: 10) {
                metricBlock(title: "TOKENS", value: Format.tokens(summary.totalTokens(includingCacheRead: prefs.menuBarIncludesCache)))
                metricBlock(title: "COST", value: Format.cost(summary.totalCost))
                metricBlock(title: "SESSIONS", value: "\(summary.sessionCount)")
            }

            if let refreshed = env.store.lastRefreshedAt {
                Text("UPDATED \(Format.relativeDate(refreshed).uppercased())")
                    .font(.sora(9, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Color.stxMuted)
            } else {
                Text(env.store.isLoading ? "SCANNING..." : "NOT UPDATED YET")
                    .font(.sora(9, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                actionButton(symbol: env.store.isLoading ? "hourglass" : "arrow.clockwise", label: "Refresh") {
                    Task { await env.store.refresh() }
                }
                .disabled(env.store.isLoading)

                actionButton(symbol: "macwindow", label: "Open main window") {
                    NotificationCenter.default.post(name: .openMainWindowFromFloatingStats, object: nil)
                }

                actionButton(symbol: "gearshape", label: "Open settings") {
                    NotificationCenter.default.post(name: .openSettingsFromFloatingStats, object: nil)
                }
            }
        }
        .padding(14)
    }

    private func header(provider: ProviderKind, period: StatsPeriod) -> some View {
        HStack(spacing: 9) {
            Image(systemName: provider.iconSystemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(period.displayName.uppercased())
                    .font(.sora(9, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityHint("Drag to move the floating tab")
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.sora(8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.stxStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
    }

    private var dragHandle: some View {
        FloatingDragHandle(
            onDragBegan: onDragBegan,
            onDragMoved: onDragMoved,
            onDragEnded: onDragEnded
        )
        .accessibilityHidden(true)
    }

    private enum Metrics {
        static let collapsedContentPadding: CGFloat = 8
    }
}

private struct FloatingTabShape: Shape {
    let edge: FloatingPanelEdge
    let cornerRadius: CGFloat
    var edgeReleaseProgress: CGFloat

    var animatableData: CGFloat {
        get { edgeReleaseProgress }
        set { edgeReleaseProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let dockedRadius = r * min(max(edgeReleaseProgress, 0), 1)
        let radii = cornerRadii(exposedRadius: r, dockedRadius: dockedRadius)
        return roundedRectPath(in: rect, radii: radii)
    }

    private func cornerRadii(exposedRadius: CGFloat, dockedRadius: CGFloat) -> CornerRadii {
        switch edge {
        case .right:
            CornerRadii(
                topLeft: exposedRadius,
                topRight: dockedRadius,
                bottomRight: dockedRadius,
                bottomLeft: exposedRadius
            )
        case .left:
            CornerRadii(
                topLeft: dockedRadius,
                topRight: exposedRadius,
                bottomRight: exposedRadius,
                bottomLeft: dockedRadius
            )
        case .top:
            CornerRadii(
                topLeft: dockedRadius,
                topRight: dockedRadius,
                bottomRight: exposedRadius,
                bottomLeft: exposedRadius
            )
        case .bottom:
            CornerRadii(
                topLeft: exposedRadius,
                topRight: exposedRadius,
                bottomRight: dockedRadius,
                bottomLeft: dockedRadius
            )
        }
    }

    private func roundedRectPath(in rect: CGRect, radii: CornerRadii) -> Path {
        let maximumRadius = min(rect.width, rect.height) / 2
        let topLeft = min(radii.topLeft, maximumRadius)
        let topRight = min(radii.topRight, maximumRadius)
        let bottomRight = min(radii.bottomRight, maximumRadius)
        let bottomLeft = min(radii.bottomLeft, maximumRadius)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }

    private struct CornerRadii {
        var topLeft: CGFloat
        var topRight: CGFloat
        var bottomRight: CGFloat
        var bottomLeft: CGFloat
    }
}

#if DEBUG
#Preview("Floating tab") {
    VStack(spacing: 24) {
        FloatingStatsPanelView(
            state: {
                let state = FloatingStatsPanelState()
                state.edge = .right
                return state
            }(),
            onHoverChanged: { _ in },
            onDragBegan: { _ in },
            onDragMoved: { _ in },
            onDragEnded: { _ in }
        )
        .environment(AppEnvironment.preview())

        FloatingStatsPanelView(
            state: {
                let state = FloatingStatsPanelState()
                state.edge = .right
                state.isExpanded = true
                return state
            }(),
            onHoverChanged: { _ in },
            onDragBegan: { _ in },
            onDragMoved: { _ in },
            onDragEnded: { _ in }
        )
        .environment(AppEnvironment.preview())
    }
    .padding(40)
}
#endif
