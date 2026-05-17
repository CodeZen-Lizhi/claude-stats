import SwiftUI

enum LeaderboardLayout {
    static let workspaceMaxWidth: CGFloat = 1120
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 52
    static let bottomPadding: CGFloat = 22
    static let columnSpacing: CGFloat = 14
    static let leftColumnWidth: CGFloat = 390
    static let detailMinWidth: CGFloat = 500
    static let wideMinimumWidth: CGFloat = leftColumnWidth + columnSpacing + detailMinWidth

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        min(workspaceMaxWidth, max(0, availableWidth - horizontalPadding * 2))
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
