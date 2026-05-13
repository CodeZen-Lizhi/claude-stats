import Foundation
import Observation

/// Time window the git view is scoped to.
enum GitRange: String, CaseIterable, Identifiable, Sendable {
    case last7Days, last30Days, last90Days
    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .last7Days: "7D"
        case .last30Days: "30D"
        case .last90Days: "90D"
        }
    }
    var dayCount: Int {
        switch self {
        case .last7Days: 7
        case .last30Days: 30
        case .last90Days: 90
        }
    }
    /// Calendar unit the correlation/timeline charts bucket by for this range.
    var bucketUnit: Calendar.Component { self == .last90Days ? .weekOfYear : .day }
}

@MainActor
@Observable
final class GitActivityViewModel {
    var range: GitRange = .last7Days {
        didSet { if range != oldValue { reloadToken &+= 1 } }
    }
    var onlyMyCommits: Bool = true {
        didSet { if onlyMyCommits != oldValue { reloadToken &+= 1 } }
    }
    private(set) var repos: [RepoActivity] = []
    private(set) var isLoading = false
    private(set) var gitAvailable = true
    private(set) var userEmail: String?

    /// Bumped whenever something the view should re-fetch for changes; the view
    /// drives `.task(id:)` off it.
    private(set) var reloadToken: UInt64 = 0

    private let calendar = Calendar.current

    func bumpReload() { reloadToken &+= 1 }

    /// Start of the current window (start of the day, `dayCount - 1` days ago).
    var windowStart: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: today) ?? today
    }

    func reload(sessions: [Session]) async {
        isLoading = true
        defer { isLoading = false }

        let cwds = Array(Set(sessions.compactMap(\.cwd)))
        let since = windowStart
        let onlyMine = onlyMyCommits

        let result = await Task.detached(priority: .userInitiated) { () -> (repos: [RepoActivity], email: String?, available: Bool) in
            let git = GitAnalyzer()
            guard git.isAvailable else { return ([], nil, false) }
            let email = git.currentUserEmail()
            let repos = git.repos(forCwds: cwds)
            let activity = git.activity(for: repos, since: since, authorEmail: onlyMine ? email : nil)
            return (activity, email, true)
        }.value

        gitAvailable = result.available
        userEmail = result.email
        repos = result.repos.sorted { $0.churn != $1.churn ? $0.churn > $1.churn : $0.commitCount > $1.commitCount }
    }

    // MARK: - Derived data

    var totalCommits: Int { repos.reduce(0) { $0 + $1.commitCount } }
    var totalInsertions: Int { repos.reduce(0) { $0 + $1.insertions } }
    var totalDeletions: Int { repos.reduce(0) { $0 + $1.deletions } }
    var totalFilesChanged: Int { repos.reduce(0) { $0 + $1.filesChanged } }
    var hasData: Bool { !repos.isEmpty }

    /// Newest-first commits across all repos, capped for the "recent" list.
    func recentCommits(limit: Int = 40) -> [GitCommit] {
        Array(repos.allCommitsNewestFirst.prefix(limit))
    }

    /// Commit buckets for one repo, oldest→newest, gap-filled across the window
    /// so the timeline reads continuously.
    func timeline(for activity: RepoActivity) -> [GitBucket] {
        let unit = range.bucketUnit
        let existing = Dictionary(
            [activity].buckets(by: unit, calendar: calendar).map { ($0.start, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        return slots(unit: unit).map { start in
            existing[start] ?? GitBucket(repoID: activity.repo.id, start: start, commitCount: 0, insertions: 0, deletions: 0)
        }
    }

    struct CorrelationPoint: Identifiable, Sendable {
        let start: Date
        let claudeTokens: Int
        let commitCount: Int
        let churn: Int
        var id: TimeInterval { start.timeIntervalSinceReferenceDate }
    }

    /// One point per time bucket: Claude tokens spent in repos we found commits
    /// for, alongside the commit count / churn in the same bucket.
    func correlation(sessions: [Session]) -> [CorrelationPoint] {
        guard hasData else { return [] }
        let unit = range.bucketUnit
        let since = windowStart
        let roots = repos.map(\.repo.rootPath)
        func belongsToTrackedRepo(_ cwd: String) -> Bool {
            roots.contains { cwd == $0 || cwd.hasPrefix($0 + "/") }
        }
        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: unit, for: date)?.start ?? date
        }

        var byStart: [Date: (tokens: Int, commits: Int, churn: Int)] = [:]
        for session in sessions {
            guard let cwd = session.cwd, belongsToTrackedRepo(cwd), let timeline = session.stats?.timeline else { continue }
            for bucket in timeline where bucket.start >= since {
                byStart[bucketStart(bucket.start), default: (0, 0, 0)].tokens += bucket.tokens
            }
        }
        for bucket in repos.buckets(by: unit, calendar: calendar) {
            byStart[bucket.start, default: (0, 0, 0)].commits += bucket.commitCount
            byStart[bucket.start, default: (0, 0, 0)].churn += bucket.churn
        }

        return slots(unit: unit).map { start in
            let v = byStart[start] ?? (0, 0, 0)
            return CorrelationPoint(start: start, claudeTokens: v.tokens, commitCount: v.commits, churn: v.churn)
        }
    }

    /// Every bucket-start in the current window, oldest→newest.
    private func slots(unit: Calendar.Component) -> [Date] {
        let endExclusive = calendar.dateInterval(of: .day, for: .now)?.end ?? Date.now
        var cursor = calendar.dateInterval(of: unit, for: windowStart)?.start ?? windowStart
        var out: [Date] = []
        while cursor < endExclusive {
            out.append(cursor)
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return out
    }
}

#if DEBUG
extension GitActivityViewModel {
    /// A view model pre-populated with canned commit activity for `#Preview`.
    /// Repo paths line up with `Session.previewSamples` so the usage/commit
    /// correlation chart lights up too.
    static func preview() -> GitActivityViewModel {
        let vm = GitActivityViewModel()
        vm.range = .last30Days
        let cal = Calendar.current
        let now = Date.now
        func at(_ daysAgo: Int, _ hour: Int = 11) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now)) ?? now
            return cal.date(byAdding: .hour, value: hour, to: day) ?? day
        }
        func commit(_ repo: GitRepo, _ daysAgo: Int, _ subject: String,
                    _ insertions: Int, _ deletions: Int, _ files: Int,
                    mine: Bool = true) -> GitCommit {
            GitCommit(hash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                      date: at(daysAgo), author: mine ? "Ada Lovelace" : "Grace Hopper",
                      authorEmail: mine ? "ada@example.com" : "grace@example.com",
                      subject: subject, insertions: insertions, deletions: deletions,
                      filesChanged: files, repoID: repo.id)
        }
        let aurora = GitRepo(rootPath: "/Users/dev/projects/aurora")
        let ledger = GitRepo(rootPath: "/Users/dev/projects/ledger")
        let designSystem = GitRepo(rootPath: "/Users/dev/work/design-system")

        let activity = [
            RepoActivity(repo: aurora, commits: [
                commit(aurora, 0, "feat: websocket reconnect with backoff", 312, 48, 7),
                commit(aurora, 0, "fix: drop stale subscriptions on close", 24, 11, 2),
                commit(aurora, 1, "refactor: extract ConnectionCoordinator", 188, 164, 5),
                commit(aurora, 3, "test: reconnect timing fixtures", 240, 6, 4),
                commit(aurora, 9, "feat: migrate settings screen to new design", 470, 90, 11),
                commit(aurora, 10, "chore: bump design-tokens dependency", 8, 8, 3, mine: false),
                commit(aurora, 16, "feat: initial websocket transport", 640, 12, 9),
            ]),
            RepoActivity(repo: ledger, commits: [
                commit(ledger, 2, "fix: off-by-one in pagination cursor", 18, 22, 3),
                commit(ledger, 2, "test: pagination edge cases", 130, 4, 2),
                commit(ledger, 6, "perf: batch balance recomputation", 92, 140, 6),
                commit(ledger, 13, "refactor: split ledger into modules", 280, 260, 8),
            ]),
            RepoActivity(repo: designSystem, commits: [
                commit(designSystem, 4, "feat: liquid-glass surface tokens", 150, 30, 5, mine: false),
                commit(designSystem, 12, "fix: dark-mode contrast on chips", 40, 38, 6),
                commit(designSystem, 22, "docs: component usage guide", 92, 4, 3),
            ]),
        ]
        vm.repos = activity.sorted { $0.churn != $1.churn ? $0.churn > $1.churn : $0.commitCount > $1.commitCount }
        vm.userEmail = "ada@example.com"
        vm.gitAvailable = true
        return vm
    }

    /// A view model in the "no git activity" state — same as the live view when
    /// none of your projects are git repos with commits in the window.
    static func previewEmpty() -> GitActivityViewModel {
        let vm = GitActivityViewModel()
        vm.gitAvailable = true
        vm.userEmail = "ada@example.com"
        return vm
    }
}
#endif
