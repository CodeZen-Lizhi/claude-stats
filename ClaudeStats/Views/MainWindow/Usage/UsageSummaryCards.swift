import SwiftUI

struct UsageSummaryCards: View {
    let summary: UsageSummary
    let includeCacheInTokens: Bool
    let cacheHitRate: Double?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card("Total tokens", Format.tokens(summary.totalTokens(includingCacheRead: includeCacheInTokens)))
                    card("Est. cost", Format.cost(summary.totalCost))
                    card("Sessions", "\(summary.sessionCount)")
                }
                GridRow {
                    card("Messages", Format.tokens(summary.messageCount))
                    card("Cache hit", cacheHitRate.map(Format.percent) ?? "--")
                    card("Cached tokens", Format.tokens(summary.totalUsage.cacheReadTokens))
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card("Total tokens", Format.tokens(summary.totalTokens(includingCacheRead: includeCacheInTokens)))
                    card("Est. cost", Format.cost(summary.totalCost))
                }
                GridRow {
                    card("Sessions", "\(summary.sessionCount)")
                    card("Messages", Format.tokens(summary.messageCount))
                }
                GridRow {
                    card("Cache hit", cacheHitRate.map(Format.percent) ?? "--")
                    card("Cached tokens", Format.tokens(summary.totalUsage.cacheReadTokens))
                }
            }
        }
    }

    private func card(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value)
    }
}

#if DEBUG
#Preview {
    UsageSummaryCards(
        summary: .empty(period: .last30Days),
        includeCacheInTokens: true,
        cacheHitRate: 0.84
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
