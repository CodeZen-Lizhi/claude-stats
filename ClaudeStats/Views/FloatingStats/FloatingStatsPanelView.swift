import SwiftUI

struct FloatingStatsPanelView: View {
    @Environment(AppEnvironment.self) private var env

    let state: FloatingStatsPanelState
    var onHoverChanged: (Bool) -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { onDragChanged($0.translation) }
            .onEnded { onDragEnded($0.translation) }
    }

    var body: some View {
        let edge = state.edge
        let shape = FloatingTabShape(edge: edge, cornerRadius: state.isExpanded ? 18 : 24)
        let size = FloatingPanelGeometry.size(edge: edge, expanded: state.isExpanded)

        ZStack {
            if state.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                collapsedContent(edge: edge)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.regularMaterial, in: shape)
        .overlay(shape.stroke(Color.stxStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 6)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .font(.sora(13))
        .tint(.stxAccent)
        .animation(.easeOut(duration: 0.16), value: state.isExpanded)
        .animation(.easeOut(duration: 0.16), value: state.edge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude Stats floating tab")
    }

    private func collapsedContent(edge: FloatingPanelEdge) -> some View {
        let title = env.preferences.selectedProvider.shortName.lowercased()
        return Text(title)
            .font(.sora(15, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .rotationEffect(rotation(for: edge))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .gesture(dragGesture)
            .accessibilityHint("Hover to expand. Drag to snap to another screen edge.")
    }

    private var expandedContent: some View {
        let prefs = env.preferences
        let provider = prefs.selectedProvider
        let summary = env.store.summary(for: prefs.menuBarPeriod, provider: provider)

        return VStack(alignment: .leading, spacing: 10) {
            header(provider: provider, period: prefs.menuBarPeriod)
                .gesture(dragGesture)

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

    private func rotation(for edge: FloatingPanelEdge) -> Angle {
        switch edge {
        case .right: .degrees(-90)
        case .left: .degrees(90)
        case .top, .bottom: .zero
        }
    }
}

private struct FloatingTabShape: Shape {
    let edge: FloatingPanelEdge
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()

        switch edge {
        case .right:
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.closeSubpath()
        return path
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
            onDragChanged: { _ in },
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
            onDragChanged: { _ in },
            onDragEnded: { _ in }
        )
        .environment(AppEnvironment.preview())
    }
    .padding(40)
}
#endif
