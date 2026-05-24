import CryptoKit
import Foundation

typealias TranscriptMessageLoader = @Sendable (Session) async -> [SessionTranscriptMessage]
typealias TranscriptAnalysisProgressHandler = @Sendable (TranscriptAnalysisProgress) async -> Void
typealias TranscriptDictionaryResolver = @Sendable (Session) async -> TechnicalTermDictionarySnapshot

struct TranscriptAnalysisService: Sendable {
    static let extractorVersion = "transcript-analysis-v3"

    private let extractor: TranscriptTermExtractor
    private let index: TranscriptAnalysisIndex
    private let maxConcurrentSessions: Int
    private let dictionaryResolver: TranscriptDictionaryResolver

    init(
        extractor: TranscriptTermExtractor = TranscriptTermExtractor(),
        index: TranscriptAnalysisIndex = TranscriptAnalysisIndex(),
        maxConcurrentSessions: Int = 4,
        dictionaryResolver: @escaping TranscriptDictionaryResolver = { _ in TechnicalTermDictionarySnapshot.fallback }
    ) {
        self.extractor = extractor
        self.index = index
        self.maxConcurrentSessions = max(1, maxConcurrentSessions)
        self.dictionaryResolver = dictionaryResolver
    }

    func analyze(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: @escaping TranscriptMessageLoader,
        forceRefresh: Bool = false,
        onProgress: TranscriptAnalysisProgressHandler? = nil
    ) async throws -> TranscriptAnalysisSnapshot {
        let started = Date()
        let dictionarySnapshots = await resolveDictionaries(for: sessions)
        let dictionaryVersionsBySessionID = Dictionary(
            uniqueKeysWithValues: dictionarySnapshots.map { ($0.key, $0.value.digest) }
        )
        let dictionarySignature = Self.dictionarySignature(
            for: sessions,
            snapshotsBySessionID: dictionarySnapshots
        )
        let engine = await extractor.engineInfo(dictionaryVersion: dictionarySignature)

        await publish(
            TranscriptAnalysisProgress(
                phase: .loadingIndex,
                total: sessions.count,
                completed: 0,
                reused: 0,
                newCount: 0,
                changed: 0,
                empty: 0,
                deleted: 0,
                currentSessionTitle: nil
            ),
            to: onProgress
        )

        let lookupStarted = Date()
        let lookups = try await index.lookup(
            provider: provider,
            sessions: sessions,
            tokenizerID: engine.tokenizerID,
            dictionaryVersion: engine.dictionaryVersion,
            dictionaryVersionsBySessionID: dictionaryVersionsBySessionID,
            forceRefresh: forceRefresh
        )
        let lookupDuration = Date().timeIntervalSince(lookupStarted)

        var pendingJobs: [(lookup: TranscriptAnalysisLookup, mode: AnalysisJob.Mode)] = []
        pendingJobs.reserveCapacity(sessions.count)
        var jobs: [AnalysisJob] = []
        let keysBySessionID = Dictionary(uniqueKeysWithValues: lookups.map { ($0.session.id, $0.key) })

        var reused = 0
        var newCount = 0
        var changed = 0
        var empty = 0

        for lookup in lookups {
            switch lookup.state {
            case .hit:
                reused += 1
            case .empty:
                empty += 1
            case .missNew:
                pendingJobs.append((lookup: lookup, mode: .new))
            case .missChanged:
                pendingJobs.append((lookup: lookup, mode: .changed))
            }
        }
        if !pendingJobs.isEmpty {
            let runtimeDictionaries = Self.runtimeDictionaries(from: dictionarySnapshots)
            jobs = pendingJobs.map { pending in
                AnalysisJob(
                    session: pending.lookup.session,
                    key: pending.lookup.key,
                    mode: pending.mode,
                    dictionary: Self.runtimeDictionary(
                        for: pending.lookup.session,
                        snapshotsBySessionID: dictionarySnapshots,
                        runtimeDictionariesByDigest: runtimeDictionaries
                    )
                )
            }
        }

        let deleted = try await index.pruneDeleted(
            provider: provider,
            liveSessionIDs: Set(sessions.map(\.id))
        )

        var completed = reused + empty
        await publish(
            TranscriptAnalysisProgress(
                phase: jobs.isEmpty ? .finalizingRanking : .analyzingTranscripts,
                total: sessions.count,
                completed: completed,
                reused: reused,
                newCount: newCount,
                changed: changed,
                empty: empty,
                deleted: deleted,
                currentSessionTitle: jobs.first?.session.stats?.title ?? jobs.first?.session.externalID
            ),
            to: onProgress
        )

        var messageLoadDuration: TimeInterval = 0
        var extractDuration: TimeInterval = 0
        var writeDuration: TimeInterval = 0

        var nextIndex = 0
        while nextIndex < jobs.count {
            try Task.checkCancellation()
            let endIndex = min(nextIndex + maxConcurrentSessions, jobs.count)
            let batch = Array(jobs[nextIndex ..< endIndex])
            nextIndex = endIndex

            try await withThrowingTaskGroup(of: AnalysisJobResult.self) { group in
                for job in batch {
                    group.addTask { [extractor, messageLoader] in
                        try Task.checkCancellation()
                        let loadStarted = Date()
                        let messages = await messageLoader(job.session)
                        let loadDuration = Date().timeIntervalSince(loadStarted)
                        guard !messages.isEmpty else {
                            return .empty(job: job, messageLoadDuration: loadDuration)
                        }

                        let extractStarted = Date()
                        let analysis = await extractor.extract(
                            session: job.session,
                            messages: messages,
                            dictionary: job.dictionary
                        )
                        return .analyzed(
                            job: job,
                            analysis: analysis,
                            messageLoadDuration: loadDuration,
                            extractDuration: Date().timeIntervalSince(extractStarted)
                        )
                    }
                }

                for try await result in group {
                    try Task.checkCancellation()
                    switch result {
                    case .analyzed(let job, let analysis, let loadDuration, let extractionDuration):
                        let writeStarted = Date()
                        try await index.writeAnalyzed(analysis, for: job.key)
                        writeDuration += Date().timeIntervalSince(writeStarted)
                        messageLoadDuration += loadDuration
                        extractDuration += extractionDuration
                        completed += 1
                        switch job.mode {
                        case .new:
                            newCount += 1
                        case .changed:
                            changed += 1
                        }
                    case .empty(let job, let loadDuration):
                        let writeStarted = Date()
                        try await index.writeEmpty(for: job.session, key: job.key)
                        writeDuration += Date().timeIntervalSince(writeStarted)
                        messageLoadDuration += loadDuration
                        completed += 1
                        empty += 1
                    }

                    await publish(
                        TranscriptAnalysisProgress(
                            phase: .analyzingTranscripts,
                            total: sessions.count,
                            completed: completed,
                            reused: reused,
                            newCount: newCount,
                            changed: changed,
                            empty: empty,
                            deleted: deleted,
                            currentSessionTitle: result.sessionTitle
                        ),
                        to: onProgress
                    )
                }
            }
        }

        await publish(
            TranscriptAnalysisProgress(
                phase: .finalizingRanking,
                total: sessions.count,
                completed: completed,
                reused: reused,
                newCount: newCount,
                changed: changed,
                empty: empty,
                deleted: deleted,
                currentSessionTitle: nil
            ),
            to: onProgress
        )

        let tfidfStarted = Date()
        let summary = TranscriptAnalysisRunSummary(
            reused: reused,
            newCount: newCount,
            changed: changed,
            empty: empty,
            deleted: deleted,
            analyzed: newCount + changed,
            indexUpdatedAt: .now
        )
        let snapshot = try await index.materializedSnapshot(
            provider: provider,
            sessions: sessions,
            keysBySessionID: keysBySessionID,
            engine: engine,
            dictionarySignature: dictionarySignature,
            runSummary: summary
        )
        let tfidfDuration = Date().timeIntervalSince(tfidfStarted)

        await publish(
            TranscriptAnalysisProgress(
                phase: .completed,
                total: sessions.count,
                completed: completed,
                reused: reused,
                newCount: newCount,
                changed: changed,
                empty: empty,
                deleted: deleted,
                currentSessionTitle: nil
            ),
            to: onProgress
        )

        Log.analysis.info(
            "Transcript analysis \(provider.rawValue, privacy: .public): sessions=\(sessions.count, privacy: .public) reused=\(reused, privacy: .public) new=\(newCount, privacy: .public) changed=\(changed, privacy: .public) empty=\(empty, privacy: .public) deleted=\(deleted, privacy: .public) lookup=\(lookupDuration, privacy: .public)s load=\(messageLoadDuration, privacy: .public)s extract=\(extractDuration, privacy: .public)s write=\(writeDuration, privacy: .public)s tfidf=\(tfidfDuration, privacy: .public)s total=\(Date().timeIntervalSince(started), privacy: .public)s"
        )
        return snapshot
    }

    static func corpusSignature(for sessions: [Session]) -> String {
        sessions
            .map { "\($0.id):\($0.fileSize):\(lastModifiedNanoseconds(for: $0))" }
            .sorted()
            .joined(separator: "|")
    }

    private func resolveDictionaries(for sessions: [Session]) async -> [String: TechnicalTermDictionarySnapshot] {
        var snapshots: [String: TechnicalTermDictionarySnapshot] = [:]
        snapshots.reserveCapacity(sessions.count)
        for session in sessions {
            snapshots[session.id] = await dictionaryResolver(session)
        }
        return snapshots
    }

    private static func dictionarySignature(
        for sessions: [Session],
        snapshotsBySessionID: [String: TechnicalTermDictionarySnapshot]
    ) -> String {
        let rows = sessions
            .map { session in
                "\(session.id):\(snapshotsBySessionID[session.id]?.digest ?? TechnicalTermDictionarySnapshot.fallback.digest)"
            }
            .sorted()
            .joined(separator: "|")
        return "dictionary-corpus-\(sha256(rows))"
    }

    private static func runtimeDictionaries(
        from snapshotsBySessionID: [String: TechnicalTermDictionarySnapshot]
    ) -> [String: TechnicalTermDictionary] {
        var dictionaries: [String: TechnicalTermDictionary] = [:]
        dictionaries.reserveCapacity(Set(snapshotsBySessionID.values.map(\.digest)).count + 1)
        for snapshot in snapshotsBySessionID.values where dictionaries[snapshot.digest] == nil {
            dictionaries[snapshot.digest] = snapshot.dictionary
        }
        let fallback = TechnicalTermDictionarySnapshot.fallback
        if dictionaries[fallback.digest] == nil {
            dictionaries[fallback.digest] = fallback.dictionary
        }
        return dictionaries
    }

    private static func runtimeDictionary(
        for session: Session,
        snapshotsBySessionID: [String: TechnicalTermDictionarySnapshot],
        runtimeDictionariesByDigest: [String: TechnicalTermDictionary]
    ) -> TechnicalTermDictionary {
        let snapshot = snapshotsBySessionID[session.id] ?? .fallback
        return runtimeDictionariesByDigest[snapshot.digest] ?? snapshot.dictionary
    }

    private func publish(
        _ progress: TranscriptAnalysisProgress,
        to handler: TranscriptAnalysisProgressHandler?
    ) async {
        guard let handler else { return }
        await handler(progress)
    }

    private static func lastModifiedNanoseconds(for session: Session) -> Int64 {
        Int64((session.lastModified.timeIntervalSince1970 * 1_000_000_000).rounded())
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct AnalysisJob: Sendable {
    enum Mode: Sendable {
        case new
        case changed
    }

    let session: Session
    let key: TranscriptAnalysisKey
    let mode: Mode
    let dictionary: TechnicalTermDictionary
}

private enum AnalysisJobResult: Sendable {
    case analyzed(
        job: AnalysisJob,
        analysis: TranscriptSessionAnalysis,
        messageLoadDuration: TimeInterval,
        extractDuration: TimeInterval
    )
    case empty(job: AnalysisJob, messageLoadDuration: TimeInterval)

    var sessionTitle: String {
        switch self {
        case .analyzed(let job, _, _, _), .empty(let job, _):
            job.session.stats?.title ?? job.session.externalID
        }
    }
}
