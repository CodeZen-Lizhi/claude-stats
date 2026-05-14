import Foundation
import Observation

/// Drives the Dashboard heatmap(s). Holds the user's choice of local data
/// source (commits vs Claude session tokens) and the visible time window,
/// plus the GitHub state (cells, status, total) and the computed Overlap.
///
/// `reload(...)` runs the local and GitHub arms in parallel; both are async
/// off-main builders, so the main actor stays responsive.
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

    enum GitHubStatus: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(login: String, syncedAt: Date?, isStale: Bool)
        case failed(reason: String)
    }

    // MARK: - User-driven state

    var localSource: LocalSource = .commits {
        didSet { if localSource != oldValue { bumpReload() } }
    }
    var range: Range = .last12Months {
        didSet { if range != oldValue { bumpReload() } }
    }
    var onlyMyCommits: Bool = true {
        didSet { if onlyMyCommits != oldValue { bumpReload() } }
    }

    // MARK: - Derived state (read-only to the view)

    private(set) var cells: [HeatmapCell] = []
    private(set) var isLoading = false
    private(set) var gitAvailable = true
    private(set) var reloadToken: UInt64 = 0

    private(set) var githubCells: [HeatmapCell] = []
    private(set) var githubStatus: GitHubStatus = .disconnected
    private(set) var githubTotalContributions: Int = 0
    private(set) var overlap: OverlapStats?

    // MARK: - Collaborators

    private let builder = DashboardActivityBuilder()
    private let github = GitHubClient()
    private let cache = GitHubCalendarCache()
    private let creds = GitHubCredentialsStore.shared

    func bumpReload() { reloadToken &+= 1 }

    func currentInterval(now: Date = .now) -> DateInterval {
        range.interval(now: now)
    }

    /// Total `value` over all local cells.
    var totalValue: Int { cells.reduce(0) { $0 + $1.value } }
    /// Distinct days with non-zero local activity.
    var activeDays: Int { cells.lazy.filter { $0.value > 0 }.count }

    // MARK: - Reload

    /// Reload both arms. `githubLogin` is the persisted login from
    /// `Preferences` — used to look up the cache when the VM has just been
    /// constructed (e.g. at app launch). `enableGitHub` lets the caller turn
    /// off the GitHub arm entirely when the user disabled it in Settings.
    func reload(sessions: [Session], githubLogin: String, enableGitHub: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let interval = currentInterval()

        async let local: Void = reloadLocal(sessions: sessions, interval: interval)
        async let remote: Void = reloadGitHub(interval: interval, expectedLogin: githubLogin, enabled: enableGitHub)
        _ = await (local, remote)

        if enableGitHub, !githubCells.isEmpty {
            overlap = OverlapStats.compute(local: cells, github: githubCells, range: interval)
        } else {
            overlap = nil
        }
    }

    private func reloadLocal(sessions: [Session], interval: DateInterval) async {
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

    private func reloadGitHub(interval: DateInterval, expectedLogin: String, enabled: Bool) async {
        guard enabled else {
            githubCells = []
            githubStatus = .disconnected
            return
        }
        guard let token = creds.readToken(), !token.isEmpty else {
            githubCells = []
            githubStatus = .disconnected
            return
        }
        // First, try cache so the panel renders instantly.
        let cached = expectedLogin.isEmpty ? nil : cache.read(login: expectedLogin)
        if let cached {
            githubCells = cached.snapshot.cells
            githubTotalContributions = cached.snapshot.totalContributions
            githubStatus = .connected(login: cached.snapshot.login, syncedAt: cached.snapshot.fetchedAt, isStale: cached.isStale)
            if !cached.isStale { return }
        } else {
            githubStatus = .connecting
        }
        await performFetch(token: token, interval: interval)
    }

    /// Force a fetch ignoring cache TTL. Caller-driven (Settings ▸ Sync now).
    func syncGitHubNow() async {
        guard let token = creds.readToken(), !token.isEmpty else {
            githubStatus = .disconnected
            return
        }
        let interval = currentInterval()
        await performFetch(token: token, interval: interval)
        if !githubCells.isEmpty {
            overlap = OverlapStats.compute(local: cells, github: githubCells, range: interval)
        }
    }

    private func performFetch(token: String, interval: DateInterval) async {
        // Don't clobber a populated cached state with "connecting" — we
        // already show stale cells.
        if githubCells.isEmpty { githubStatus = .connecting }
        do {
            let snapshot = try await github.fetchCalendar(token: token, from: interval.start, to: interval.end)
            githubCells = snapshot.cells
            githubTotalContributions = snapshot.totalContributions
            githubStatus = .connected(login: snapshot.login, syncedAt: snapshot.fetchedAt, isStale: false)
            do {
                try cache.write(snapshot)
            } catch {
                Log.network.error("GitHub cache write failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch let err as GitHubClient.ClientError {
            handle(err)
        } catch {
            githubStatus = .failed(reason: "Unexpected error: \(error.localizedDescription)")
        }
    }

    private func handle(_ error: GitHubClient.ClientError) {
        switch error {
        case .unauthorized:
            creds.deleteToken()
            githubCells = []
            githubTotalContributions = 0
            githubStatus = .failed(reason: "Token rejected. Re-enter your PAT in Settings.")
        case .rateLimited:
            // Keep cached cells if any; surface retry hint.
            githubStatus = .failed(reason: String(describing: error))
        case .graphQL, .http, .network, .decoding:
            // Keep whatever cached cells we showed first; surface reason.
            githubStatus = .failed(reason: String(describing: error))
        }
    }

    // MARK: - User actions

    /// Save the token, force-fetch once, return the resolved login on
    /// success. Throws on Keychain save / network / GraphQL failure so the
    /// Settings view can show the error inline.
    @discardableResult
    func connectGitHub(token: String) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitHubClient.ClientError.unauthorized }
        try creds.saveToken(trimmed)
        githubStatus = .connecting
        let interval = currentInterval()
        do {
            let snapshot = try await github.fetchCalendar(token: trimmed, from: interval.start, to: interval.end)
            githubCells = snapshot.cells
            githubTotalContributions = snapshot.totalContributions
            githubStatus = .connected(login: snapshot.login, syncedAt: snapshot.fetchedAt, isStale: false)
            try? cache.write(snapshot)
            overlap = OverlapStats.compute(local: cells, github: githubCells, range: interval)
            return snapshot.login
        } catch {
            // Don't keep a bad token in the keychain.
            creds.deleteToken()
            githubStatus = .disconnected
            throw error
        }
    }

    /// Wipe token, cells, and cache for `login`.
    func disconnectGitHub(login: String) {
        creds.deleteToken()
        if !login.isEmpty { cache.delete(login: login) }
        githubCells = []
        githubTotalContributions = 0
        githubStatus = .disconnected
        overlap = nil
    }
}
