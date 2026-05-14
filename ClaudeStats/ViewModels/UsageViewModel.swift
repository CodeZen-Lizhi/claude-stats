import Foundation
import Observation

/// How the Usage trend panel is drawn.
enum TrendChartStyle: Sendable, Hashable { case line, bar }

/// Vertical scaling for the trend panel — `log` (ln(1+x)) compresses big gaps
/// between models so the smaller ones stay legible.
enum TrendScaleMode: Sendable, Hashable { case linear, log }

/// UI state for the Usage screen: the selected ``StatsPeriod`` plus how the
/// trend panel is drawn. The summary itself is derived from a ``SessionStore``
/// passed in by the view.
@MainActor
@Observable
final class UsageViewModel {
    var period: StatsPeriod = .allTime
    /// Line vs. bar for the trend panel (ignored for the Today/hourly view,
    /// which is always a smoothed line).
    var chartStyle: TrendChartStyle = .line
    /// Linear vs. ln scaling (only used in line mode on non-Today periods).
    var scaleMode: TrendScaleMode = .linear
    /// When on, the trend panel stacks by token *type* (Output / Input /
    /// Cache Write / Cache Read) instead of by model — surfaces cache-hit
    /// efficiency at a glance.
    var stackByType: Bool = false

    func summary(from store: SessionStore, provider: ProviderKind) -> UsageSummary {
        store.summary(for: period, provider: provider)
    }
}
