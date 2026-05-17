import SwiftUI

enum LeaderboardLayout {
    static let workspaceMaxWidth: CGFloat = 980
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 52
    static let bottomPadding: CGFloat = 22
    static let columnSpacing: CGFloat = 14
    static let headerContentSpacing: CGFloat = 20
    static let leftColumnWidth: CGFloat = 390
    static let detailMinWidth: CGFloat = 500
    static let wideMinimumWidth: CGFloat = leftColumnWidth + columnSpacing + detailMinWidth

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        min(workspaceMaxWidth, max(0, availableWidth - horizontalPadding * 2))
    }
}

struct LeaderboardWideWorkspaceLayout: Layout {
    let leftWidth: CGFloat
    let detailMinWidth: CGFloat
    let columnSpacing: CGFloat
    let headerSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let availableWidth = proposal.width ?? leftWidth + columnSpacing + detailMinWidth
        let detailWidth = max(detailMinWidth, availableWidth - leftWidth - columnSpacing)
        let sizes = measuredSizes(subviews: subviews, detailWidth: detailWidth)
        return CGSize(
            width: leftWidth + columnSpacing + detailWidth,
            height: sizes.headerHeight + headerSpacing + sizes.lowerHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let detailWidth = max(detailMinWidth, bounds.width - leftWidth - columnSpacing)
        let sizes = measuredSizes(subviews: subviews, detailWidth: detailWidth)
        let lowerY = bounds.minY + sizes.headerHeight + headerSpacing

        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: sizes.headerHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: lowerY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: sizes.lowerHeight)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX + leftWidth + columnSpacing, y: lowerY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: sizes.lowerHeight)
        )
    }

    private func measuredSizes(subviews: Subviews, detailWidth: CGFloat) -> (headerHeight: CGFloat, lowerHeight: CGFloat) {
        let headerHeight = subviews[0].sizeThatFits(ProposedViewSize(width: leftWidth, height: nil)).height
        let leftHeight = subviews[1].sizeThatFits(ProposedViewSize(width: leftWidth, height: nil)).height
        let rightHeight = subviews[2].sizeThatFits(ProposedViewSize(width: detailWidth, height: nil)).height
        return (headerHeight, max(leftHeight, rightHeight))
    }
}

enum LeaderboardFormat {
    static func score(_ score: Int64, metric: LeaderboardMetric) -> String {
        switch metric {
        case .tokensWithCache, .tokensWithoutCacheRead:
            return Format.tokens(Int(clamping: score))
        case .activityMinutes:
            return Format.duration(TimeInterval(score) * 60)
        }
    }

    static func delta(_ score: Int64, metric: LeaderboardMetric) -> String {
        score == 0 ? "0" : Self.score(score, metric: metric)
    }

    static func avatarSeed(for score: LeaderboardScore) -> String {
        score.avatarSeed ?? score.userHash ?? score.nickname
    }
}

extension LeaderboardMetric {
    var symbolName: String {
        switch self {
        case .tokensWithCache: "bolt.circle"
        case .tokensWithoutCacheRead: "bolt.slash.circle"
        case .activityMinutes: "figure.walk.circle"
        }
    }
}

extension LeaderboardPeriod {
    var chipLabel: String {
        switch self {
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .allTime: "All"
        }
    }

    var symbolName: String {
        switch self {
        case .day: "sun.max"
        case .week: "calendar"
        case .month: "calendar.badge.clock"
        case .allTime: "infinity"
        }
    }
}

extension View {
    func leaderboardSegmentedBackground() -> some View {
        padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    func leaderboardSelectedSegment(_ isSelected: Bool) -> some View {
        background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.stxPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.stxStroke, lineWidth: 1)
                    )
            }
        }
    }
}
