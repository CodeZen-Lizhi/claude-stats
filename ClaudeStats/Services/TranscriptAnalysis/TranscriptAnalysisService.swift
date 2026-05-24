import Foundation

typealias TranscriptMessageLoader = @Sendable (Session) async -> [SessionTranscriptMessage]
typealias TranscriptAnalysisProgressHandler = @Sendable (TranscriptAnalysisProgress) async -> Void

struct TranscriptAnalysisService: Sendable {
    static let extractorVersion = "transcript-analysis-v2"

    private let extractor: TranscriptTermExtractor
    private let tfidf = TranscriptTFIDFAnalyzer()
    private let index: TranscriptAnalysisIndex
    private let maxConcurrentSessions: Int

    init(
        extractor: TranscriptTermExtractor = TranscriptTermExtractor(),
        index: TranscriptAnalysisIndex = TranscriptAnalysisIndex(),
        maxConcurrentSessions: Int = 4
    ) {
        self.extractor = extractor
        self.index = index
        self.maxConcurrentSessions = max(1, maxConcurrentSessions)
    }

    func analyze(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: @escaping TranscriptMessageLoader,
        forceRefresh: Bool = false,
        onProgress: TranscriptAnalysisProgressHandler? = nil
    ) async throws -> TranscriptAnalysisSnapshot {
        let started = Date()
        let engine = await extractor.engineInfo

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
            forceRefresh: forceRefresh
        )
        let lookupDuration = Date().timeIntervalSince(lookupStarted)

        var analyses: [TranscriptSessionAnalysis] = []
        analyses.reserveCapacity(sessions.count)
        var jobs: [AnalysisJob] = []
        jobs.reserveCapacity(sessions.count)

        var reused = 0
        var newCount = 0
        var changed = 0
        var empty = 0

        for lookup in lookups {
            switch lookup.state {
            case .hit(let analysis):
                analyses.append(analysis)
                reused += 1
            case .empty:
                empty += 1
            case .missNew:
                jobs.append(AnalysisJob(session: lookup.session, key: lookup.key, mode: .new))
            case .missChanged:
                jobs.append(AnalysisJob(session: lookup.session, key: lookup.key, mode: .changed))
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
                        let analysis = await extractor.extract(session: job.session, messages: messages)
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
                        analyses.append(analysis)
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

        let order = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($0.element.id, $0.offset) })
        analyses.sort { (order[$0.sessionID] ?? Int.max) < (order[$1.sessionID] ?? Int.max) }

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
        let snapshot = tfidf.snapshot(
            provider: provider,
            sessions: sessions,
            sessionAnalyses: analyses,
            engine: engine,
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
}

private struct AnalysisJob: Sendable, Hashable {
    enum Mode: Sendable, Hashable {
        case new
        case changed
    }

    let session: Session
    let key: TranscriptAnalysisKey
    let mode: Mode
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
