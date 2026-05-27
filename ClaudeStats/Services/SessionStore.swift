import Foundation
import Observation

typealias TranscriptMessageLoader = @Sendable (Session) async -> [SessionTranscriptMessage]
typealias TranscriptTrasher = @MainActor @Sendable (URL) throws -> Void

/// The app's source of truth for sessions and aggregate usage. Owns the
/// scan/parse pipeline and a parse cache keyed by transcript metadata
/// so a refresh only re-parses transcripts that actually changed.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var historicalSessions: [Session] = []
    private(set) var isLoading = false
    private(set) var lastRefreshedAt: Date?
    /// Whether any provider's on-disk data directory exists — drives the
    /// "no Codex data found" empty state.
    private(set) var dataDirectoryExists: Bool
    @ObservationIgnored var onRefresh: (() -> Void)?

    private let registry: ProviderRegistry
    private let pricing: ModelPricing
    private let usageLedger: UsageLedgerStore
    private let deletedSessions: DeletedSessionStore
    private let trashTranscript: TranscriptTrasher
    private var cache: [String: CacheEntry] = [:]
    private var usageEventsSnapshot: [UsageLedgerEvent] = []
    private var usageEventsByProviderSnapshot: [ProviderKind: [UsageLedgerEvent]] = [:]
    private var summaryCache: [UsageSummaryCacheKey: UsageSummary] = [:]
    private var summaryCacheDay: Date?
    private(set) var gitAttributionRevision: Int = 0
    private var gitAttributionSignature: [String] = []
    private var autoRefreshTask: Task<Void, Never>?

    private struct CacheEntry {
        let fileSize: Int64
        let lastModified: Date
        let stats: SessionStats
    }

    private struct UsageSummaryCacheKey: Hashable, Sendable {
        let period: StatsPeriod
        let provider: ProviderKind?
    }

    private struct UsageSnapshotCache: Sendable {
        let day: Date
        let eventsByProvider: [ProviderKind: [UsageLedgerEvent]]
        let summaries: [UsageSummaryCacheKey: UsageSummary]
    }

    /// Max transcripts parsed concurrently.
    private static let parseBatchSize = 16

    init(
        registry: ProviderRegistry,
        pricing: ModelPricing,
        usageLedger: UsageLedgerStore = UsageLedgerStore(),
        deletedSessions: DeletedSessionStore = DeletedSessionStore(),
        trashTranscript: @escaping TranscriptTrasher = SessionStore.moveTranscriptToTrash
    ) {
        self.registry = registry
        self.pricing = pricing
        self.usageLedger = usageLedger
        self.deletedSessions = deletedSessions
        self.trashTranscript = trashTranscript
        self.dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }
    }

    // MARK: Queries

    /// All discovered sessions belonging to `provider`.
    func sessions(for provider: ProviderKind) -> [Session] {
        sessions.filter { $0.provider == provider }
    }

    private func sessions(matching provider: ProviderKind?) -> [Session] {
        guard let provider else { return sessions }
        return sessions.filter { $0.provider == provider }
    }

    /// Whether `provider`'s on-disk data directory exists.
    func dataDirectoryExists(for provider: ProviderKind) -> Bool {
        registry.provider(for: provider)?.dataDirectoryExists ?? false
    }

    /// `provider`'s data directory path, for the empty-state message.
    func dataDirectoryPath(for provider: ProviderKind) -> String? {
        registry.provider(for: provider)?.dataDirectoryPath
    }

    /// Pretty label for a model id under `provider`. Falls back to the raw id
    /// when the provider is unknown — never returns a placeholder so callers
    /// can drop it straight into a label.
    func displayName(forModel id: String, provider: ProviderKind) -> String {
        registry.provider(for: provider)?.displayName(forModel: id) ?? id
    }

    func cacheHitRate(for usage: TokenUsage, provider: ProviderKind) -> Double? {
        registry.provider(for: provider)?.cacheHitRate(for: usage) ?? usage.cacheHitRate
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        guard let provider = registry.provider(for: session.provider) else { return [] }
        var messages = await provider.transcriptMessages(for: session)
        messages.append(contentsOf: await childTranscriptMessages(from: session.childSessions))
        return messages
    }

    func transcriptMessageLoader(for provider: ProviderKind) -> TranscriptMessageLoader? {
        guard let provider = registry.provider(for: provider) else { return nil }
        return { session in
            await provider.transcriptMessages(for: session)
        }
    }

    func summary(for period: StatsPeriod, provider: ProviderKind? = nil, now: Date = .now) -> UsageSummary {
        if let cached = cachedSummary(for: period, provider: provider, now: now) {
            return cached
        }
        return UsageSummary.make(period: period, events: ledgerEvents(matching: provider), now: now)
    }

    func summary(for selection: PeriodSelection, provider: ProviderKind? = nil, now: Date = .now) -> UsageSummary {
        switch selection {
        case .preset(let period):
            return summary(for: period, provider: provider, now: now)
        case .custom(let start, let end):
            return UsageSummary.makeCustom(start: start, end: end, events: ledgerEvents(matching: provider))
        }
    }

    func sessions(in period: StatsPeriod, provider: ProviderKind? = nil, now: Date = .now) -> [Session] {
        sessions(matching: provider).filter { period.contains($0.stats?.lastActivity ?? $0.lastModified, now: now) }
    }

    func usageEvents(provider: ProviderKind? = nil) async -> [UsageLedgerEvent] {
        await usageLedger.events(provider: provider)
    }

    func usageEventsSnapshot(provider: ProviderKind? = nil) -> [UsageLedgerEvent] {
        ledgerEvents(matching: provider)
    }

    var gitAttributionSessions: [Session] {
        historicalSessions
    }

    private func ledgerEvents(matching provider: ProviderKind?) -> [UsageLedgerEvent] {
        guard let provider else { return usageEventsSnapshot }
        return usageEventsByProviderSnapshot[provider] ?? []
    }

    private func cachedSummary(for period: StatsPeriod, provider: ProviderKind?, now: Date) -> UsageSummary? {
        if period != .allTime {
            let day = Calendar.current.startOfDay(for: now)
            guard summaryCacheDay == day else { return nil }
        }
        return summaryCache[UsageSummaryCacheKey(period: period, provider: provider)]
    }

    nonisolated private static func makeUsageSnapshotCache(
        events: [UsageLedgerEvent],
        providers: [ProviderKind],
        now: Date,
        calendar: Calendar = .current
    ) -> UsageSnapshotCache {
        let day = calendar.startOfDay(for: now)
        let eventsByProvider = Dictionary(grouping: events, by: \.provider)
        var summaries: [UsageSummaryCacheKey: UsageSummary] = [:]
        for period in StatsPeriod.allCases {
            summaries[UsageSummaryCacheKey(period: period, provider: nil)] = UsageSummary.make(
                period: period,
                events: events,
                now: now,
                calendar: calendar
            )
            for provider in providers {
                summaries[UsageSummaryCacheKey(period: period, provider: provider)] = UsageSummary.make(
                    period: period,
                    events: eventsByProvider[provider] ?? [],
                    now: now,
                    calendar: calendar
                )
            }
        }
        return UsageSnapshotCache(day: day, eventsByProvider: eventsByProvider, summaries: summaries)
    }

    nonisolated private static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }
        let refreshStartedAt = Date()
        isLoading = true
        defer { isLoading = false }

        let discoveryStartedAt = Date()
        var discovered: [Session] = []
        for provider in registry.providers {
            discovered += await provider.discoverSessions()
        }
        let deletedRecords = await deletedSessions.records()
        let deletedIndex = DeletedSessionIndex(records: deletedRecords)
        discovered.removeAll { deletedIndex.contains($0) }
        discovered.sort { $0.lastModified > $1.lastModified }
        dataDirectoryExists = registry.providers.contains { $0.dataDirectoryExists }
        let discoveryDuration = Date().timeIntervalSince(discoveryStartedAt)

        let ledgerStartedAt = Date()
        await usageLedger.beginPersistenceBatch()
        await usageLedger.markSeen(discovered)
        let ledgerMarkSeenDuration = Date().timeIntervalSince(ledgerStartedAt)

        let workPlanningStartedAt = Date()
        let providerByKind = Dictionary(uniqueKeysWithValues: registry.providers.map { ($0.kind, $0) })
        var work: [RefreshWorkItem] = []
        for session in discovered {
            if let entry = cache[session.id],
               entry.fileSize == session.fileSize,
               entry.lastModified == session.lastModified {
                continue
            }
            guard let state = await usageLedger.parseState(for: session.id) else {
                work.append(.rebuild(session, .preserveLedgerOnNil))
                continue
            }
            if Self.canRestoreFromLedger(session, state: state) {
                continue
            }
            if Self.canAppendUsage(session, state: state) {
                work.append(.append(session, state))
            } else if state.hasViewableTranscript == false {
                work.append(.rebuild(session, .preserveLedgerOnNil))
            } else {
                work.append(.rebuild(session, .replaceLedgerOnNil))
            }
        }
        let workPlanningDuration = Date().timeIntervalSince(workPlanningStartedAt)

        let parseStartedAt = Date()
        var index = 0
        var appendedCount = 0
        var rebuiltCount = 0
        while index < work.count {
            let batch = work[index ..< min(index + Self.parseBatchSize, work.count)]
            index += Self.parseBatchSize
            await withTaskGroup(of: RefreshParseResult.self) { group in
                for item in batch {
                    switch item {
                    case .append(let session, let state):
                        guard let provider = providerByKind[session.provider] else { continue }
                        group.addTask {
                            if let result = await provider.parseUsageAppend(session, from: state) {
                                return .appended(session, result)
                            }
                            return .rebuilt(session, await provider.parse(session), .preserveLedgerOnNil)
                        }
                    case .rebuild(let session, let nilPolicy):
                        guard let provider = providerByKind[session.provider] else { continue }
                        group.addTask { .rebuilt(session, await provider.parse(session), nilPolicy) }
                    }
                }
                for await result in group {
                    switch result {
                    case .appended(let session, let append):
                        await usageLedger.appendEvents(for: session, result: append)
                        if let stats = await usageLedger.stats(for: session) {
                            let state = await usageLedger.parseState(for: session.id)
                            cache[session.id] = CacheEntry(
                                fileSize: state?.fileSize ?? session.fileSize,
                                lastModified: state?.lastModified ?? session.lastModified,
                                stats: stats
                            )
                        } else {
                            await usageLedger.markUnviewable(for: session)
                            cache.removeValue(forKey: session.id)
                        }
                        appendedCount += 1
                    case .rebuilt(let session, let stats, let nilPolicy):
                        if let stats {
                            let displayStats = stats.applyingTitleOverride(session.titleOverride)
                            await usageLedger.replaceEvents(for: session, stats: displayStats)
                            let ledgerStats = (await usageLedger.stats(for: session) ?? displayStats)
                                .applyingTitleOverride(session.titleOverride)
                            cache[session.id] = CacheEntry(
                                fileSize: session.fileSize,
                                lastModified: session.lastModified,
                                stats: ledgerStats
                            )
                        } else {
                            switch nilPolicy {
                            case .preserveLedgerOnNil:
                                await usageLedger.markUnviewable(for: session)
                            case .replaceLedgerOnNil:
                                await usageLedger.clearEvents(for: session)
                                await usageLedger.markUnviewable(for: session)
                            }
                            cache.removeValue(forKey: session.id)
                        }
                        rebuiltCount += 1
                    }
                }
            }
        }
        let parseDuration = Date().timeIntervalSince(parseStartedAt)

        let statsStartedAt = Date()
        let liveIDs = Set(discovered.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) }

        var withStats = discovered
        for i in withStats.indices {
            if let stats = cache[withStats[i].id]?.stats {
                withStats[i].stats = stats.applyingTitleOverride(withStats[i].titleOverride)
            } else if let stats = await usageLedger.stats(for: withStats[i]) {
                let displayStats = stats.applyingTitleOverride(withStats[i].titleOverride)
                withStats[i].stats = displayStats
                cache[withStats[i].id] = CacheEntry(
                    fileSize: withStats[i].fileSize,
                    lastModified: withStats[i].lastModified,
                    stats: displayStats
                )
            }
        }
        let statsDuration = Date().timeIntervalSince(statsStartedAt)

        let graphStartedAt = Date()
        // Drop transcripts that parsed to nothing (only queue-ops / snapshots).
        let parsedSessions = withStats.filter { $0.stats != nil }
        let deletedRecordSessions = await deletedRecordSessions(from: deletedRecords)
        let allSessionInputs = Self.applyingDeletedParentLinks(
            to: parsedSessions + deletedRecordSessions,
            records: deletedRecords
        )
        let allSessionGraph = await buildSessionGraph(from: allSessionInputs, providers: providerByKind)
        historicalSessions = allSessionGraph
        let newGitAttributionSignature = Self.gitAttributionSignature(from: allSessionGraph)
        if newGitAttributionSignature != gitAttributionSignature {
            gitAttributionSignature = newGitAttributionSignature
            gitAttributionRevision &+= 1
        }
        sessions = Self.visibleSessionGraph(from: allSessionGraph, deletedIndex: deletedIndex)
        await usageLedger.syncParentSessionIDs(
            mapping: Self.parentMapping(from: sessions),
            liveSessionIDs: liveIDs
        )
        let graphDuration = Date().timeIntervalSince(graphStartedAt)

        let snapshotStartedAt = Date()
        await usageLedger.endPersistenceBatch()
        let events = await usageLedger.events()
        let providerKinds = registry.providers.map(\.kind)
        let snapshotCache = await Task.detached(priority: .utility) {
            Self.makeUsageSnapshotCache(
                events: events,
                providers: providerKinds,
                now: Date()
            )
        }.value
        usageEventsSnapshot = events
        usageEventsByProviderSnapshot = snapshotCache.eventsByProvider
        summaryCache = snapshotCache.summaries
        summaryCacheDay = snapshotCache.day
        let snapshotDuration = Date().timeIntervalSince(snapshotStartedAt)

        let refreshedAt = Date()
        lastRefreshedAt = refreshedAt
        let totalDuration = refreshedAt.timeIntervalSince(refreshStartedAt)
        Log.store.notice("Refreshed: \(self.sessions.count) visible, \(events.count) events, \(work.count) planned, \(appendedCount) appended, \(rebuiltCount) rebuilt")
        Log.store.info("Refresh timings total=\(Self.formatDuration(totalDuration), privacy: .public)s discover=\(Self.formatDuration(discoveryDuration), privacy: .public)s markSeen=\(Self.formatDuration(ledgerMarkSeenDuration), privacy: .public)s plan=\(Self.formatDuration(workPlanningDuration), privacy: .public)s parse=\(Self.formatDuration(parseDuration), privacy: .public)s stats=\(Self.formatDuration(statsDuration), privacy: .public)s graph=\(Self.formatDuration(graphDuration), privacy: .public)s snapshot=\(Self.formatDuration(snapshotDuration), privacy: .public)s")
        onRefresh?()
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

    func deleteSession(_ session: Session) async -> SessionDeletionResult {
        await deleteSessions([session])
    }

    func deleteSessions(_ selectedSessions: [Session]) async -> SessionDeletionResult {
        let targets = Self.expandedDeletionTargets(from: selectedSessions)
        let now = Date()
        var deletedIDs = Set<String>()
        var failures: [SessionDeletionFailure] = []

        for session in targets {
            let record = DeletedSessionRecord(session: session, deletedAt: now)
            do {
                try await deletedSessions.add([record])
                do {
                    try trashTranscript(URL(fileURLWithPath: session.filePath))
                    deletedIDs.insert(session.id)
                } catch {
                    try? await deletedSessions.remove(sessionIDs: [session.id])
                    failures.append(Self.deletionFailure(for: session, error: error))
                }
            } catch {
                failures.append(Self.deletionFailure(for: session, error: error))
            }
        }

        if !deletedIDs.isEmpty {
            await refresh()
        }
        return SessionDeletionResult(deletedIDs: deletedIDs, failures: failures)
    }

    private func childTranscriptMessages(from children: [Session]) async -> [SessionTranscriptMessage] {
        var messages: [SessionTranscriptMessage] = []
        for child in children.sorted(by: Self.childSort) {
            messages.append(Self.childSessionMarker(for: child))
            guard let childProvider = registry.provider(for: child.provider) else { continue }
            let childMessages = await childProvider.transcriptMessages(for: child)
            messages.append(contentsOf: childMessages.map { message in
                SessionTranscriptMessage(
                    id: "\(child.id)::\(message.id)",
                    role: message.role,
                    text: message.text,
                    timestamp: message.timestamp,
                    model: message.model
                )
            })
            messages.append(contentsOf: await childTranscriptMessages(from: child.childSessions))
        }
        return messages
    }

    private func deletedRecordSessions(from records: [DeletedSessionRecord]) async -> [Session] {
        var out: [Session] = []
        for record in records {
            let shell = record.session(stats: nil)
            let stats = await usageLedger.stats(for: shell)
            out.append(record.session(stats: stats))
        }
        return out
    }
}

#if DEBUG
extension SessionStore {
    /// Inject canned sessions without touching disk — for SwiftUI previews.
    func loadPreviewSessions(_ sessions: [Session]) {
        self.sessions = sessions
        self.historicalSessions = sessions
        let events = Self.previewEvents(from: sessions)
        let now = Date()
        let snapshotCache = Self.makeUsageSnapshotCache(
            events: events,
            providers: Array(Set(sessions.map(\.provider))),
            now: now
        )
        self.usageEventsSnapshot = events
        self.usageEventsByProviderSnapshot = snapshotCache.eventsByProvider
        self.summaryCache = snapshotCache.summaries
        self.summaryCacheDay = snapshotCache.day
        self.gitAttributionSignature = Self.gitAttributionSignature(from: sessions)
        self.gitAttributionRevision &+= 1
        self.lastRefreshedAt = now
        self.dataDirectoryExists = !sessions.isEmpty
    }

    private static func previewEvents(from sessions: [Session]) -> [UsageLedgerEvent] {
        sessions.flatMap { session -> [UsageLedgerEvent] in
            guard let stats = session.stats else { return [] }
            if !stats.billableMessages.isEmpty {
                return stats.billableMessages.enumerated().compactMap { index, bill in
                    guard let timestamp = bill.timestamp else { return nil }
                    return UsageLedgerEvent(
                        eventKey: bill.hash ?? "\(session.provider.rawValue)|\(session.id)|preview|\(index)",
                        sessionID: session.id,
                        provider: session.provider,
                        model: bill.model,
                        timestamp: timestamp,
                        usage: bill.usage,
                        cost: bill.cost,
                        sourcePath: session.filePath,
                        sequenceIndex: index,
                        parentSessionID: session.agentInfo?.parentSessionID
                    )
                }
            }
            let timestamp = stats.lastActivity ?? session.lastModified
            return stats.models.enumerated().map { index, model in
                UsageLedgerEvent(
                    eventKey: "\(session.provider.rawValue)|\(session.id)|preview-model|\(index)",
                    sessionID: session.id,
                    provider: session.provider,
                    model: model.model,
                    timestamp: timestamp,
                    usage: model.usage,
                    cost: model.costEstimate,
                    sourcePath: session.filePath,
                    sequenceIndex: index,
                    parentSessionID: session.agentInfo?.parentSessionID
                )
            }
        }
    }
}
#endif

private extension SessionStore {
    static func gitAttributionSignature(from sessions: [Session]) -> [String] {
        sessions
            .map {
                "\($0.id)|\($0.provider.rawValue)|\($0.cwd ?? "")|\($0.projectDirectoryName)|\($0.filePath)"
            }
            .sorted()
    }

    struct DeletedSessionIndex {
        let ids: Set<String>
        let paths: Set<String>

        init(records: [DeletedSessionRecord]) {
            self.ids = Set(records.map(\.sessionID))
            self.paths = Set(records.map(\.filePath))
        }

        func contains(_ session: Session) -> Bool {
            ids.contains(session.id) || paths.contains(session.filePath)
        }
    }

    enum RefreshWorkItem: Sendable {
        case append(Session, UsageLedgerParseState)
        case rebuild(Session, RebuildNilPolicy)
    }

    enum RefreshParseResult: Sendable {
        case appended(Session, UsageLedgerAppendResult)
        case rebuilt(Session, SessionStats?, RebuildNilPolicy)
    }

    enum RebuildNilPolicy: Sendable {
        case preserveLedgerOnNil
        case replaceLedgerOnNil
    }

    static func moveTranscriptToTrash(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
    }

    static func expandedDeletionTargets(from sessions: [Session]) -> [Session] {
        var ordered: [Session] = []
        var seen = Set<String>()

        func append(_ session: Session) {
            for child in session.childSessions {
                append(child)
            }
            guard seen.insert(session.id).inserted else { return }
            ordered.append(session)
        }

        for session in sessions {
            append(session)
        }
        return ordered
    }

    static func applyingDeletedParentLinks(to sessions: [Session], records: [DeletedSessionRecord]) -> [Session] {
        var parentByChild: [String: String] = [:]
        for record in records {
            for childID in record.childSessionIDs {
                parentByChild[childID] = record.sessionID
            }
        }
        guard !parentByChild.isEmpty else { return sessions }

        return sessions.map { session in
            guard let parentID = parentByChild[session.id],
                  session.agentInfo?.parentSessionID == nil else {
                return session
            }
            var copy = session
            var agentInfo = copy.agentInfo ?? SessionAgentInfo(
                threadSource: "subagent",
                parentSessionID: nil,
                nickname: nil,
                role: nil,
                path: nil
            )
            agentInfo.threadSource = agentInfo.threadSource ?? "subagent"
            agentInfo.parentSessionID = parentID
            copy.agentInfo = agentInfo
            return copy
        }
    }

    static func visibleSessionGraph(from roots: [Session], deletedIndex: DeletedSessionIndex) -> [Session] {
        roots.compactMap { visibleSession(from: $0, deletedIndex: deletedIndex) }
            .sorted { $0.lastModified > $1.lastModified }
    }

    static func visibleSession(from session: Session, deletedIndex: DeletedSessionIndex) -> Session? {
        guard !deletedIndex.contains(session) else { return nil }
        var copy = session
        copy.childSessions = session.childSessions.compactMap { visibleSession(from: $0, deletedIndex: deletedIndex) }
            .sorted(by: Self.childSort)
        return copy
    }

    static func deletionFailure(for session: Session, error: Error) -> SessionDeletionFailure {
        SessionDeletionFailure(
            sessionID: session.id,
            title: session.stats.flatMap { $0.title.isEmpty ? nil : $0.title } ?? session.titleFallback ?? session.externalID,
            message: error.localizedDescription
        )
    }

    static func canRestoreFromLedger(_ session: Session, state: UsageLedgerParseState) -> Bool {
        state.hasViewableTranscript != false
            && state.provider == session.provider
            && state.sourcePath == session.filePath
            && state.fileSize == session.fileSize
            && state.lastModified == session.lastModified
    }

    static func canAppendUsage(_ session: Session, state: UsageLedgerParseState) -> Bool {
        guard state.hasViewableTranscript != false,
              state.provider == session.provider,
              state.sourcePath == session.filePath,
              state.fileSize >= 0,
              session.fileSize > state.fileSize,
              session.lastModified >= state.lastModified else {
            return false
        }
        return state.lastParsedByteOffset == UInt64(max(state.fileSize, 0))
    }

    static func parentMapping(from roots: [Session]) -> [String: String] {
        var mapping: [String: String] = [:]
        for root in roots {
            collectParentMapping(rootSessionID: root.id, children: root.childSessions, into: &mapping)
        }
        return mapping
    }

    static func collectParentMapping(rootSessionID: String, children: [Session], into mapping: inout [String: String]) {
        for child in children {
            mapping[child.id] = rootSessionID
            collectParentMapping(rootSessionID: rootSessionID, children: child.childSessions, into: &mapping)
        }
    }

    func buildSessionGraph(
        from source: [Session],
        providers: [ProviderKind: any Provider]
    ) async -> [Session] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        var parentByChild: [String: String] = [:]

        for child in source {
            guard let parentID = child.agentInfo?.parentSessionID,
                  parentID != child.id,
                  let parent = sessionsByID[parentID],
                  parent.provider == child.provider,
                  !Self.createsCycle(childID: child.id, parentID: parentID, parentByChild: parentByChild) else {
                continue
            }
            parentByChild[child.id] = parentID
        }

        let unresolvedChildren = source.filter { session in
            session.agentInfo?.threadSource == "subagent"
                && session.agentInfo?.parentSessionID == nil
                && parentByChild[session.id] == nil
        }
        if !unresolvedChildren.isEmpty {
            let intervals = await taskIntervals(for: source.filter { parentByChild[$0.id] == nil }, providers: providers)
            for child in unresolvedChildren {
                guard let parentID = conservativeParentID(
                    for: child,
                    in: source,
                    intervals: intervals,
                    excluded: Set(parentByChild.keys)
                ),
                    sessionsByID[parentID] != nil,
                    !Self.createsCycle(childID: child.id, parentID: parentID, parentByChild: parentByChild) else {
                    continue
                }
                parentByChild[child.id] = parentID
            }
        }

        var childrenByParent: [String: [String]] = [:]
        for (childID, parentID) in parentByChild {
            childrenByParent[parentID, default: []].append(childID)
        }

        let rootIDs = source
            .map(\.id)
            .filter { parentByChild[$0] == nil }
        let roots = rootIDs.compactMap { rootID in
            populateSessionGraph(
                rootID,
                sessionsByID: sessionsByID,
                childrenByParent: childrenByParent,
                ancestors: []
            )
        }
        return roots.sorted { $0.lastModified > $1.lastModified }
    }

    static func createsCycle(childID: String, parentID: String, parentByChild: [String: String]) -> Bool {
        var cursor: String? = parentID
        var seen: Set<String> = [childID]
        while let current = cursor {
            if seen.contains(current) { return true }
            seen.insert(current)
            cursor = parentByChild[current]
        }
        return false
    }

    func populateSessionGraph(
        _ id: String,
        sessionsByID: [String: Session],
        childrenByParent: [String: [String]],
        ancestors: Set<String>
    ) -> Session? {
        guard var session = sessionsByID[id], !ancestors.contains(id) else { return nil }
        var nextAncestors = ancestors
        nextAncestors.insert(id)
        session.childSessions = (childrenByParent[id] ?? [])
            .compactMap {
                populateSessionGraph(
                    $0,
                    sessionsByID: sessionsByID,
                    childrenByParent: childrenByParent,
                    ancestors: nextAncestors
                )
            }
            .sorted(by: Self.childSort)
        if !session.childSessions.isEmpty, let stats = session.stats {
            session.stats = Self.mergedStats(
                parent: stats,
                children: session.childSessions.compactMap(\.stats)
            )
        }
        return session
    }

    func taskIntervals(
        for sessions: [Session],
        providers: [ProviderKind: any Provider]
    ) async -> [String: [SessionTaskInterval]] {
        await withTaskGroup(of: (String, [SessionTaskInterval]).self, returning: [String: [SessionTaskInterval]].self) { group in
            for session in sessions {
                guard let provider = providers[session.provider] else { continue }
                group.addTask { (session.id, await provider.taskIntervals(for: session)) }
            }
            var out: [String: [SessionTaskInterval]] = [:]
            for await (sessionID, intervals) in group where !intervals.isEmpty {
                out[sessionID] = intervals
            }
            return out
        }
    }

    func conservativeParentID(
        for child: Session,
        in sessions: [Session],
        intervals: [String: [SessionTaskInterval]],
        excluded: Set<String>
    ) -> String? {
        guard let childStats = child.stats,
              let childStart = childStats.firstActivity ?? childStats.lastActivity,
              let childEnd = childStats.lastActivity ?? childStats.firstActivity else {
            return nil
        }
        let tolerance: TimeInterval = 120
        let matches = sessions.compactMap { candidate -> String? in
            guard candidate.id != child.id,
                  candidate.provider == child.provider,
                  !excluded.contains(candidate.id),
                  relatedWorkingDirectory(candidate.cwd, child.cwd),
                  let windows = intervals[candidate.id] else {
                return nil
            }
            let fits = windows.contains { interval in
                childStart >= interval.start.addingTimeInterval(-tolerance)
                    && childEnd <= interval.end.addingTimeInterval(tolerance)
            }
            return fits ? candidate.id : nil
        }
        return Set(matches).count == 1 ? matches.first : nil
    }

    func relatedWorkingDirectory(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        let l = URL(fileURLWithPath: lhs).standardizedFileURL.path
        let r = URL(fileURLWithPath: rhs).standardizedFileURL.path
        return l.hasPrefix(r + "/") || r.hasPrefix(l + "/")
    }

    static func childSort(_ lhs: Session, _ rhs: Session) -> Bool {
        let l = lhs.stats?.firstActivity ?? lhs.stats?.lastActivity ?? lhs.lastModified
        let r = rhs.stats?.firstActivity ?? rhs.stats?.lastActivity ?? rhs.lastModified
        return l < r
    }

    static func mergedStats(parent: SessionStats, children: [SessionStats]) -> SessionStats {
        let all = [parent] + children
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]

        for stats in all {
            for model in stats.models {
                var acc = perModel[model.model] ?? (0, .zero, .zero)
                acc.count += model.messageCount
                acc.usage += model.usage
                acc.cost += model.costEstimate
                perModel[model.model] = acc
            }
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }

        return SessionStats(
            title: parent.title,
            messageCount: all.reduce(0) { $0 + $1.messageCount },
            firstActivity: all.compactMap(\.firstActivity).min(),
            lastActivity: all.compactMap(\.lastActivity).max(),
            models: models,
            timeline: all.flatMap(\.timeline).mergedByModelBucket(),
            activityIntervals: all.flatMap(\.activityIntervals).sorted { $0.start < $1.start },
            billableMessages: all.flatMap(\.billableMessages)
        )
    }

    static func childSessionMarker(for child: Session) -> SessionTranscriptMessage {
        let stats = child.stats
        let ownTotals = ownTotals(for: child)
        let tokens = Format.tokens(ownTotals.tokens)
        let cost = Format.cost(ownTotals.cost)
        let label = child.agentInfo?.displayTitle ?? child.projectDisplayName
        return SessionTranscriptMessage(
            id: "\(child.id)::subagent-marker",
            role: .system,
            text: "Subagent: \(label)\nTokens: \(tokens)   Cost: \(cost)   Session: \(child.externalID)",
            timestamp: stats?.firstActivity ?? child.lastModified,
            model: stats?.models.first?.model
        )
    }

    static func ownTotals(for session: Session) -> (tokens: Int, cost: Double) {
        guard let stats = session.stats else { return (0, 0) }
        let childTokens = session.childSessions.reduce(0) { partial, child in
            partial + (child.stats?.totalTokens(includingCacheRead: true) ?? 0)
        }
        let childCost = session.childSessions.reduce(0) { partial, child in
            partial + (child.stats?.totalCost ?? 0)
        }
        return (
            max(0, stats.totalTokens(includingCacheRead: true) - childTokens),
            max(0, stats.totalCost - childCost)
        )
    }
}
