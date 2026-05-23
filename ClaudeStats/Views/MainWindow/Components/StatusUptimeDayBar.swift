import SwiftUI

struct StatusUptimeDayBar: View {
    let color: Color
    let tooltip: String

    @State private var isHovering = false

    private static let height: CGFloat = 34
    private static let hoverScale: CGFloat = 1.18
    private static let tooltipGap: CGFloat = 24
    private static let hoverAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.18)

    private static var hoverOutset: CGFloat {
        height * (hoverScale - 1) / 2
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .scaleEffect(y: isHovering ? Self.hoverScale : 1, anchor: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .overlay(alignment: .top) {
            if isHovering {
                StatusUptimeTooltip(text: tooltip)
                    .alignmentGuide(.top) { dimensions in
                        dimensions[.bottom]
                    }
                    .offset(y: -(Self.hoverOutset + Self.tooltipGap))
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .zIndex(isHovering ? 1 : 0)
        .onHover { hovering in
            withAnimation(Self.hoverAnimation) {
                isHovering = hovering
            }
        }
    }
}

private struct StatusUptimeTooltip: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.sora(10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: 260)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            TooltipArrow()
                .fill(Color.black)
                .frame(width: 10, height: 5)
        }
        .fixedSize()
        .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
    }
}

private struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
