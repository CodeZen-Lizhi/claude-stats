import Foundation
import Observation

/// UI state for the Usage screen: the selected ``StatsPeriod``. The summary
/// itself is derived from a ``SessionStore`` passed in by the view.
@MainActor
@Observable
final class UsageViewModel {
    var period: StatsPeriod = .allTime

    func summary(from store: SessionStore) -> UsageSummary {
        store.summary(for: period)
    }
}
