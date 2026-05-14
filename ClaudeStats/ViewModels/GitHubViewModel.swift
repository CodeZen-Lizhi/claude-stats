import Foundation
import Observation

/// Owns the GitHub contributions calendar: credentials, fetch, cache, and the
/// resulting [HeatmapCell] series. Extracted from the Dashboard VM so the
/// Dashboard stays a local-only overview and the GitHub heatmap lives on the
/// Git page (where it sits next to commit activity it gets compared against).
///
/// `Settings` writes the token through `connect(token:)` / `disconnect(login:)`
/// and triggers refreshes through `syncNow()`. The view-side `reload(...)`
/// reads the cache for an instant first frame, then re-fetches in the
/// background if the cache is stale.
@MainActor
@Observable
final class GitHubViewModel {
    enum Status: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(login: String, syncedAt: Date?, isStale: Bool)
        case failed(reason: String)
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

    var range: Range = .last12Months {
        didSet { if range != oldValue { reloadToken &+= 1 } }
    }

    private(set) var cells: [HeatmapCell] = []
    private(set) var status: Status = .disconnected
    private(set) var totalContributions: Int = 0
    private(set) var reloadToken: UInt64 = 0

    private let client = GitHubClient()
    private let cache = GitHubCalendarCache()
    private let creds = GitHubCredentialsStore.shared

    func bumpReload() { reloadToken &+= 1 }

    func currentInterval(now: Date = .now) -> DateInterval {
        range.interval(now: now)
    }

    /// View-side entry point. `expectedLogin` comes from `Preferences`; used to
    /// look up the on-disk cache so the heatmap renders instantly. `enabled`
    /// lets the caller turn the GitHub arm off entirely.
    func reload(expectedLogin: String, enabled: Bool) async {
        guard enabled else {
            cells = []
            status = .disconnected
            return
        }
        guard let token = creds.readToken(), !token.isEmpty else {
            cells = []
            status = .disconnected
            return
        }
        let interval = currentInterval()
        let cached = expectedLogin.isEmpty ? nil : cache.read(login: expectedLogin)
        if let cached {
            cells = cached.snapshot.cells
            totalContributions = cached.snapshot.totalContributions
            status = .connected(login: cached.snapshot.login, syncedAt: cached.snapshot.fetchedAt, isStale: cached.isStale)
            if !cached.isStale { return }
        } else {
            status = .connecting
        }
        await performFetch(token: token, interval: interval)
    }

    /// Force a fetch ignoring cache TTL. Used by Settings ▸ Sync now and by
    /// the Git page's refresh button.
    func syncNow() async {
        guard let token = creds.readToken(), !token.isEmpty else {
            status = .disconnected
            return
        }
        await performFetch(token: token, interval: currentInterval())
    }

    private func performFetch(token: String, interval: DateInterval) async {
        if cells.isEmpty { status = .connecting }
        do {
            let snapshot = try await client.fetchCalendar(token: token, from: interval.start, to: interval.end)
            cells = snapshot.cells
            totalContributions = snapshot.totalContributions
            status = .connected(login: snapshot.login, syncedAt: snapshot.fetchedAt, isStale: false)
            do {
                try cache.write(snapshot)
            } catch {
                Log.network.error("GitHub cache write failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch let err as GitHubClient.ClientError {
            handle(err)
        } catch {
            status = .failed(reason: "Unexpected error: \(error.localizedDescription)")
        }
    }

    private func handle(_ error: GitHubClient.ClientError) {
        switch error {
        case .unauthorized:
            creds.deleteToken()
            cells = []
            totalContributions = 0
            status = .failed(reason: "Token rejected. Re-enter your PAT in Settings.")
        case .rateLimited, .graphQL, .http, .network, .decoding:
            status = .failed(reason: String(describing: error))
        }
    }

    /// Save the token, force-fetch once, return the resolved login on success.
    /// Throws on Keychain save / network / GraphQL failure so the Settings view
    /// can show the error inline.
    @discardableResult
    func connect(token: String) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitHubClient.ClientError.unauthorized }
        try creds.saveToken(trimmed)
        status = .connecting
        let interval = currentInterval()
        do {
            let snapshot = try await client.fetchCalendar(token: trimmed, from: interval.start, to: interval.end)
            cells = snapshot.cells
            totalContributions = snapshot.totalContributions
            status = .connected(login: snapshot.login, syncedAt: snapshot.fetchedAt, isStale: false)
            try? cache.write(snapshot)
            return snapshot.login
        } catch {
            creds.deleteToken()
            status = .disconnected
            throw error
        }
    }

    /// Wipe token, cells, and on-disk cache for `login`.
    func disconnect(login: String) {
        creds.deleteToken()
        if !login.isEmpty { cache.delete(login: login) }
        cells = []
        totalContributions = 0
        status = .disconnected
    }
}
