import Foundation
import Observation

/// The app's source of truth for sessions and aggregate usage. Owns the
/// scan/parse pipeline and a parse cache keyed by `(session id, file size)`
/// so a refresh only re-parses transcripts that actually changed.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var lastRefreshedAt: Date?
    /// Whether any provider's on-disk data directory exists — drives the
    /// "no Claude Code data found" empty state.
    private(set) var dataDirectoryExists: Bool

    private let registry: ProviderRegistry
    private let pricing: ModelPricing
    private var cache: [String: CacheEntry] = [:]
    private var autoRefreshTask: Task<Void, Never>?

    private struct CacheEntry { let fileSize: Int64; let stats: SessionStats }

    /// Max transcripts parsed concurrently.
    private static let parseBatchSize = 16

    init(registry: ProviderRegistry, pricing: ModelPricing) {
        self.registry = registry
        self.pricing = pricing
        self.dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }
    }

    // MARK: Queries

    func summary(for period: StatsPeriod, now: Date = .now) -> UsageSummary {
        UsageSummary.make(period: period, sessions: sessions, pricing: pricing, now: now)
    }

    func summary(for selection: PeriodSelection, now: Date = .now) -> UsageSummary {
        switch selection {
        case .preset(let period):
            return summary(for: period, now: now)
        case .custom(let start, let end):
            return UsageSummary.makeCustom(start: start, end: end, sessions: sessions, pricing: pricing)
        }
    }

    func sessions(in period: StatsPeriod, now: Date = .now) -> [Session] {
        sessions.filter { period.contains($0.stats?.lastActivity ?? $0.lastModified, now: now) }
    }

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var discovered: [Session] = []
        for provider in registry.providers {
            discovered += await provider.discoverSessions()
        }
        discovered.sort { $0.lastModified > $1.lastModified }
        dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }

        let providerByKind = Dictionary(uniqueKeysWithValues: registry.providers.map { ($0.kind, $0) })
        let stale = discovered.filter { cache[$0.id]?.fileSize != $0.fileSize }

        var index = 0
        while index < stale.count {
            let batch = stale[index ..< min(index + Self.parseBatchSize, stale.count)]
            index += Self.parseBatchSize
            await withTaskGroup(of: (String, Int64, SessionStats?).self) { group in
                for session in batch {
                    guard let provider = providerByKind[session.provider] else { continue }
                    group.addTask { (session.id, session.fileSize, await provider.parse(session)) }
                }
                for await (id, size, stats) in group {
                    if let stats { cache[id] = CacheEntry(fileSize: size, stats: stats) }
                }
            }
        }

        let liveIDs = Set(discovered.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) }

        var withStats = discovered
        for i in withStats.indices { withStats[i].stats = cache[withStats[i].id]?.stats }
        // Drop transcripts that parsed to nothing (only queue-ops / snapshots).
        sessions = withStats.filter { $0.stats != nil }
        lastRefreshedAt = .now
        Log.store.notice("Refreshed: \(self.sessions.count) sessions visible, \(stale.count) re-parsed")
    }

    // MARK: Auto-refresh

    func startAutoRefresh(every interval: TimeInterval) {
        autoRefreshTask?.cancel()
        guard interval > 0 else { autoRefreshTask = nil; return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}

#if DEBUG
extension SessionStore {
    /// Inject canned sessions without touching disk — for SwiftUI previews.
    func loadPreviewSessions(_ sessions: [Session]) {
        self.sessions = sessions
        self.lastRefreshedAt = .now
        self.dataDirectoryExists = !sessions.isEmpty
    }
}
#endif
