import SwiftUI

/// Three small "All / 30d / 7d" chips at the top-right of the Dashboard.
/// Scopes the 8 stat cards only — the heatmap below them stays fixed at the
/// 3-month rolling window regardless of selection.
struct RangeChips: View {
    @Binding var period: StatsPeriod

    /// The chips we surface here, in display order. `.today` is intentionally
    /// omitted — the Dashboard story is "what does my recent activity look
    /// like", not "what happened today".
    static let supported: [StatsPeriod] = [.allTime, .last30Days, .last7Days]

    var body: some View {
        PillSegmentedBar(
            Self.supported,
            selection: $period
        ) { value, _ in
            Text(Self.label(for: value))
        }
    }

    private static func label(for period: StatsPeriod) -> String {
        switch period {
        case .allTime: L10n.string("range.all", defaultValue: "All")
        case .last30Days: "30d"
        case .last7Days: "7d"
        case .today: L10n.string("stats.period.today", defaultValue: "Today")
        }
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State var p: StatsPeriod = .last30Days
        var body: some View {
            RangeChips(period: $p).padding(24).frame(width: 360)
        }
    }
    return Wrap().background(Color.stxBackground)
}
#endif
