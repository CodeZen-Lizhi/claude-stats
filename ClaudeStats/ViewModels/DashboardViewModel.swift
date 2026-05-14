import Foundation
import Observation

/// Drives the Dashboard heatmap. Holds the user's choice of local data source
/// (commits vs Claude session tokens) and the visible time window, and asks
/// ``DashboardActivityBuilder`` to produce ``HeatmapCell``s off the main actor.
@MainActor
@Observable
final class DashboardViewModel {
    enum LocalSource: String, CaseIterable, Identifiable, Sendable {
        case commits, sessions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .commits: "Commits"
            case .sessions: "Claude sessions"
            }
        }
        var unitLabel: String {
            switch self {
            case .commits: "commits"
            case .sessions: "tokens"
            }
        }
    }

    enum Range: String, CaseIterable, Identifiable, Sendable {
        case last12Months, thisYear
        var id: String { rawValue }
        var shortLabel: String {
            switch self {
            case .last12Months: "12M"
            case .thisYear: "YTD"
            }
        }
        func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
            switch self {
            case .last12Months:
                let endExclusive = calendar.dateInterval(of: .day, for: now)?.end ?? now
                let start = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now)) ?? now
                return DateInterval(start: start, end: endExclusive)
            case .thisYear:
                let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
                let endExclusive = calendar.dateInterval(of: .day, for: now)?.end ?? now
                return DateInterval(start: start, end: endExclusive)
            }
        }
    }

    var localSource: LocalSource = .commits {
        didSet { if localSource != oldValue { bumpReload() } }
    }
    var range: Range = .last12Months {
        didSet { if range != oldValue { bumpReload() } }
    }
    var onlyMyCommits: Bool = true {
        didSet { if onlyMyCommits != oldValue { bumpReload() } }
    }

    private(set) var cells: [HeatmapCell] = []
    private(set) var isLoading = false
    private(set) var gitAvailable = true
    private(set) var reloadToken: UInt64 = 0

    private let builder = DashboardActivityBuilder()

    func bumpReload() { reloadToken &+= 1 }

    /// The currently selected visible window. Recomputed against `now` on every
    /// access so an unused window stays correct after a date change.
    func currentInterval(now: Date = .now) -> DateInterval {
        range.interval(now: now)
    }

    /// Total `value` over all cells — shown in the panel header ("247 commits"
    /// or "1.2M tokens").
    var totalValue: Int { cells.reduce(0) { $0 + $1.value } }

    /// Distinct days with non-zero activity in the window.
    var activeDays: Int { cells.lazy.filter { $0.value > 0 }.count }

    func reload(sessions: [Session]) async {
        isLoading = true
        defer { isLoading = false }
        let interval = currentInterval()
        switch localSource {
        case .commits:
            let result = await builder.commitCells(sessions: sessions, range: interval, onlyMyCommits: onlyMyCommits)
            gitAvailable = result.gitAvailable
            cells = result.cells
        case .sessions:
            gitAvailable = true
            cells = await builder.sessionCells(sessions: sessions, range: interval)
        }
    }
}
