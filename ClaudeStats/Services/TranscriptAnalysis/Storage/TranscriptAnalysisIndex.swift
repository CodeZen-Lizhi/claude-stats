import CryptoKit
import Foundation

struct TranscriptAnalysisKey: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let extractorVersion: String
    let tokenizerID: String
    let analysisVersion: String
    let optionsDigest: String
    let provider: ProviderKind
    let sessionID: String
    let filePathHash: String
    let fileSize: Int64
    let lastModifiedNanoseconds: Int64

    var digest: String {
        Self.sha256([
            "\(schemaVersion)",
            extractorVersion,
            tokenizerID,
            analysisVersion,
            optionsDigest,
            provider.rawValue,
            sessionID,
            filePathHash,
            "\(fileSize)",
            "\(lastModifiedNanoseconds)",
        ].joined(separator: "|"))
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum TranscriptAnalysisLookupState: Sendable, Hashable {
    case hit
    case empty
    case missNew
    case missChanged
}

struct TranscriptAnalysisLookup: Sendable, Hashable {
    let session: Session
    let key: TranscriptAnalysisKey
    let state: TranscriptAnalysisLookupState
}

actor TranscriptAnalysisIndex {
    static let analysisCacheSchemaVersion = 1
    static let defaultOptionsDigest = "default"

    private let url: URL
    private let schemaVersion: Int
    private var connection: SQLiteConnection?

    init(url: URL? = nil, schemaVersion: Int = TranscriptAnalysisIndex.analysisCacheSchemaVersion) {
        self.url = url ?? Self.defaultDatabaseURL()
        self.schemaVersion = schemaVersion
    }

    func key(
        for session: Session,
        tokenizerID: String,
        analysisVersion: String,
        extractorVersion: String = TranscriptAnalysisService.extractorVersion,
        optionsDigest: String = TranscriptAnalysisIndex.defaultOptionsDigest
    ) -> TranscriptAnalysisKey {
        TranscriptAnalysisKey(
            schemaVersion: schemaVersion,
            extractorVersion: extractorVersion,
            tokenizerID: tokenizerID,
            analysisVersion: analysisVersion,
            optionsDigest: optionsDigest,
            provider: session.provider,
            sessionID: session.id,
            filePathHash: Self.sha256(session.filePath),
            fileSize: session.fileSize,
            lastModifiedNanoseconds: Self.lastModifiedNanoseconds(for: session)
        )
    }

    func lookup(
        provider: ProviderKind,
        sessions: [Session],
        tokenizerID: String,
        analysisVersion: String,
        analysisVersionsBySessionID: [String: String] = [:],
        extractorVersion: String = TranscriptAnalysisService.extractorVersion,
        optionsDigest: String = TranscriptAnalysisIndex.defaultOptionsDigest,
        forceRefresh: Bool = false
    ) throws -> [TranscriptAnalysisLookup] {
        let connection = try openConnection()
        let keyedSessions = sessions.map { session in
            (
                session: session,
                key: key(
                    for: session,
                    tokenizerID: tokenizerID,
                    analysisVersion: analysisVersionsBySessionID[session.id] ?? analysisVersion,
                    extractorVersion: extractorVersion,
                    optionsDigest: optionsDigest
                )
            )
        }

        let cachedRows = forceRefresh
            ? [:]
            : try cachedSessionRows(
                for: keyedSessions.map { $0.key.digest },
                connection: connection
            )
        if !cachedRows.isEmpty {
            try touch(keyDigests: Array(cachedRows.keys), connection: connection)
        }

        var validCachedRows = cachedRows
        let invalidAnalyzedDigests = try invalidAnalyzedKeyDigests(
            in: cachedRows,
            connection: connection
        )
        for keyDigest in invalidAnalyzedDigests {
            try delete(keyDigest: keyDigest, connection: connection)
            validCachedRows.removeValue(forKey: keyDigest)
        }
        let missingSessionIDs = Set(keyedSessions.compactMap { item -> String? in
            if forceRefresh { return item.session.id }
            return validCachedRows[item.key.digest] == nil ? item.session.id : nil
        })
        let priorSessionIDs = try priorSessionIDs(
            provider: provider,
            sessionIDs: missingSessionIDs,
            connection: connection
        )

        var out: [TranscriptAnalysisLookup] = []
        out.reserveCapacity(sessions.count)

        for item in keyedSessions {
            if !forceRefresh, let cached = validCachedRows[item.key.digest] {
                switch cached.status {
                case .analyzed:
                    out.append(TranscriptAnalysisLookup(session: item.session, key: item.key, state: .hit))
                case .empty:
                    out.append(TranscriptAnalysisLookup(session: item.session, key: item.key, state: .empty))
                }
                continue
            }

            out.append(TranscriptAnalysisLookup(
                session: item.session,
                key: item.key,
                state: priorSessionIDs.contains(item.session.id) ? .missChanged : .missNew
            ))
        }
        return out
    }

    func writeAnalyzed(_ analysis: TranscriptSessionAnalysis, for key: TranscriptAnalysisKey) throws {
        let connection = try openConnection()
        let savedAt = Date().timeIntervalSince1970
        try connection.transaction {
            try delete(provider: key.provider, sessionID: key.sessionID, connection: connection)
            try insertSessionRow(
                key: key,
                status: .analyzed,
                sessionTitle: analysis.sessionTitle,
                projectName: analysis.projectName,
                termCount: analysis.terms.count,
                savedAt: savedAt,
                connection: connection
            )
            for (index, term) in analysis.terms.enumerated() {
                try insertTerm(term, ordinal: index, keyDigest: key.digest, connection: connection)
            }
        }
    }

    func writeEmpty(for session: Session, key: TranscriptAnalysisKey) throws {
        let connection = try openConnection()
        let savedAt = Date().timeIntervalSince1970
        try connection.transaction {
            try delete(provider: key.provider, sessionID: key.sessionID, connection: connection)
            try insertSessionRow(
                key: key,
                status: .empty,
                sessionTitle: session.stats?.title ?? session.externalID,
                projectName: session.projectDisplayName,
                termCount: 0,
                savedAt: savedAt,
                connection: connection
            )
        }
    }

    func pruneDeleted(provider: ProviderKind, liveSessionIDs: Set<String>) throws -> Int {
        let connection = try openConnection()
        let select = try connection.prepare("SELECT DISTINCT session_id FROM session_analysis WHERE provider = ?")
        try select.bind(provider.rawValue, at: 1)
        var stale: [String] = []
        while try select.step() {
            guard let sessionID = select.columnString(0), !liveSessionIDs.contains(sessionID) else { continue }
            stale.append(sessionID)
        }

        guard !stale.isEmpty else { return 0 }
        try connection.transaction {
            for sessionID in stale {
                try delete(provider: provider, sessionID: sessionID, connection: connection)
            }
        }
        return stale.count
    }

    func materializedSnapshot(
        provider: ProviderKind,
        sessions: [Session],
        keysBySessionID: [String: TranscriptAnalysisKey],
        engine: TranscriptAnalysisEngineInfo,
        analysisSignature: String,
        runSummary: TranscriptAnalysisRunSummary,
        extractorVersion: String = TranscriptAnalysisService.extractorVersion,
        optionsDigest: String = TranscriptAnalysisIndex.defaultOptionsDigest,
        now: Date = .now
    ) throws -> TranscriptAnalysisSnapshot {
        let connection = try openConnection()
        let scopeDigest = Self.corpusScopeDigest(
            provider: provider,
            schemaVersion: schemaVersion,
            extractorVersion: extractorVersion,
            tokenizerID: engine.tokenizerID,
            optionsDigest: optionsDigest
        )
        let activeMembers = try activeAnalyzedMembers(
            sessions: sessions,
            keysBySessionID: keysBySessionID,
            connection: connection
        )
        let sessionSetDigest = Self.sessionSetDigest(for: activeMembers)

        try connection.transaction {
            try reconcileCorpusMembers(
                scopeDigest: scopeDigest,
                activeMembers: activeMembers,
                connection: connection
            )
            try upsertCorpusState(
                scopeDigest: scopeDigest,
                provider: provider,
                extractorVersion: extractorVersion,
                tokenizerID: engine.tokenizerID,
                optionsDigest: optionsDigest,
                sessionSetDigest: sessionSetDigest,
                analysisSignature: analysisSignature,
                sessionCount: sessions.count,
                analyzedSessionCount: activeMembers.count,
                updatedAt: now.timeIntervalSince1970,
                connection: connection
            )
        }

        let terms = try readCorpusTerms(
            scopeDigest: scopeDigest,
            documentCount: max(activeMembers.count, 1),
            connection: connection
        )
        let analyses = try readAnalyses(
            for: activeMembers,
            keysByDigest: Dictionary(uniqueKeysWithValues: keysBySessionID.values.map { ($0.digest, $0) }),
            connection: connection
        )
        return TranscriptAnalysisSnapshot(
            provider: provider,
            generatedAt: now,
            sessionCount: sessions.count,
            analyzedSessionCount: activeMembers.count,
            terms: terms,
            sessionAnalyses: analyses,
            engine: engine,
            analysisSignature: analysisSignature,
            runSummary: runSummary
        )
    }

    func removeAll() throws {
        let connection = try openConnection()
        try connection.transaction {
            try connection.execute("DELETE FROM corpus_term_examples")
            try connection.execute("DELETE FROM corpus_term_aliases")
            try connection.execute("DELETE FROM corpus_terms")
            try connection.execute("DELETE FROM corpus_members")
            try connection.execute("DELETE FROM corpus_state")
            try connection.execute("DELETE FROM session_analysis")
        }
    }

    func databaseURL() -> URL { url }

    private func openConnection() throws -> SQLiteConnection {
        if let connection { return connection }
        let connection = try SQLiteConnection(url: url)
        try TranscriptAnalysisIndexSchema.migrate(connection)
        self.connection = connection
        return connection
    }

    private func cachedSessionRows(
        for keyDigests: [String],
        connection: SQLiteConnection
    ) throws -> [String: CachedSessionRow] {
        var rows: [String: CachedSessionRow] = [:]
        for batch in Self.batches(of: Array(Set(keyDigests))) {
            let statement = try connection.prepare(
                """
                SELECT key_digest, status, session_title, project_name, term_count
                FROM session_analysis
                WHERE key_digest IN (\(Self.placeholders(count: batch.count)))
                """
            )
            try bind(batch, to: statement)

            while try statement.step() {
                guard let keyDigest = statement.columnString(0),
                      let statusRaw = statement.columnString(1),
                      let status = RowStatus(rawValue: statusRaw),
                      let sessionTitle = statement.columnString(2),
                      let projectName = statement.columnString(3) else {
                    continue
                }
                rows[keyDigest] = CachedSessionRow(
                    status: status,
                    sessionTitle: sessionTitle,
                    projectName: projectName,
                    termCount: statement.columnInt(4)
                )
            }
        }
        return rows
    }

    private func invalidAnalyzedKeyDigests(
        in rows: [String: CachedSessionRow],
        connection: SQLiteConnection
    ) throws -> [String] {
        let analyzedWithTerms = rows.compactMap { keyDigest, row -> String? in
            row.status == .analyzed && row.termCount > 0 ? keyDigest : nil
        }
        guard !analyzedWithTerms.isEmpty else { return [] }

        var present: Set<String> = []
        for batch in Self.batches(of: analyzedWithTerms) {
            let statement = try connection.prepare(
                """
                SELECT DISTINCT key_digest
                FROM session_terms
                WHERE key_digest IN (\(Self.placeholders(count: batch.count)))
                """
            )
            try bind(batch, to: statement)
            while try statement.step() {
                if let keyDigest = statement.columnString(0) {
                    present.insert(keyDigest)
                }
            }
        }
        return analyzedWithTerms.filter { !present.contains($0) }
    }

    private func readAnalyses(
        for rowsByDigest: [String: CachedSessionRow],
        keysByDigest: [String: TranscriptAnalysisKey],
        connection: SQLiteConnection
    ) throws -> [String: TranscriptSessionAnalysis] {
        let keyDigests = Array(rowsByDigest.keys)
        guard !keyDigests.isEmpty else { return [:] }

        let examplesByDigest = try readExamples(
            for: rowsByDigest,
            keysByDigest: keysByDigest,
            connection: connection
        )
        let termsByDigest = try readTerms(
            for: keyDigests,
            examplesByDigest: examplesByDigest,
            connection: connection
        )

        var analyses: [String: TranscriptSessionAnalysis] = [:]
        analyses.reserveCapacity(rowsByDigest.count)
        for (keyDigest, row) in rowsByDigest {
            guard let key = keysByDigest[keyDigest] else { continue }
            let terms = termsByDigest[keyDigest] ?? []
            guard row.termCount == 0 || !terms.isEmpty else { continue }
            analyses[keyDigest] = TranscriptSessionAnalysis(
                sessionID: key.sessionID,
                sessionTitle: row.sessionTitle,
                projectName: row.projectName,
                terms: terms
            )
        }
        return analyses
    }

    private func readAnalyses(
        for members: [CorpusMember],
        keysByDigest: [String: TranscriptAnalysisKey],
        connection: SQLiteConnection
    ) throws -> [TranscriptSessionAnalysis] {
        let rowsByDigest = try cachedSessionRows(
            for: members.map(\.keyDigest),
            connection: connection
        )
        let analysesByDigest = try readAnalyses(
            for: rowsByDigest.filter { $0.value.status == .analyzed },
            keysByDigest: keysByDigest,
            connection: connection
        )
        return members
            .sorted { $0.ordinal < $1.ordinal }
            .compactMap { analysesByDigest[$0.keyDigest] }
    }

    private func readTerms(
        for keyDigests: [String],
        examplesByDigest: [String: [Int: TranscriptTermExample]],
        connection: SQLiteConnection
    ) throws -> [String: [TranscriptSessionTerm]] {
        var termsByDigest: [String: [TranscriptSessionTerm]] = [:]
        for batch in Self.batches(of: keyDigests) {
            let statement = try connection.prepare(
                """
                SELECT key_digest, ordinal, canonical, display_name, kind, frequency, weight,
                       role_user, role_assistant, role_tool, role_system,
                       source_dictionary, source_natural_language, source_jieba, source_code,
                       source_path, source_command, source_error, source_project
                FROM session_terms
                WHERE key_digest IN (\(Self.placeholders(count: batch.count)))
                ORDER BY key_digest ASC, ordinal ASC
                """
            )
            try bind(batch, to: statement)

            while try statement.step() {
                let ordinal = statement.columnInt(1)
                guard let keyDigest = statement.columnString(0),
                      let canonical = statement.columnString(2),
                      let displayName = statement.columnString(3),
                      let kindRaw = statement.columnString(4),
                      let kind = TranscriptTermKind(rawValue: kindRaw) else {
                    continue
                }
                let roleCounts = TranscriptRoleCounts(
                    user: statement.columnInt(7),
                    assistant: statement.columnInt(8),
                    tool: statement.columnInt(9),
                    system: statement.columnInt(10)
                )
                let sourceCounts = TranscriptSourceCounts(
                    naturalLanguage: statement.columnInt(12),
                    jieba: statement.columnInt(13),
                    code: statement.columnInt(14),
                    path: statement.columnInt(15),
                    command: statement.columnInt(16),
                    error: statement.columnInt(17),
                    project: statement.columnInt(18)
                )
                termsByDigest[keyDigest, default: []].append(TranscriptSessionTerm(
                    canonical: canonical,
                    displayName: displayName,
                    kind: kind,
                    frequency: statement.columnInt(5),
                    weight: statement.columnDouble(6),
                    roleCounts: roleCounts,
                    sourceCounts: sourceCounts,
                    example: examplesByDigest[keyDigest]?[ordinal]
                ))
            }
        }
        return termsByDigest
    }

    private func readExamples(
        for rowsByDigest: [String: CachedSessionRow],
        keysByDigest: [String: TranscriptAnalysisKey],
        connection: SQLiteConnection
    ) throws -> [String: [Int: TranscriptTermExample]] {
        var examplesByDigest: [String: [Int: TranscriptTermExample]] = [:]
        for batch in Self.batches(of: Array(rowsByDigest.keys)) {
            let statement = try connection.prepare(
                """
                SELECT key_digest, term_ordinal, id, role, excerpt, timestamp_seconds
                FROM term_examples
                WHERE key_digest IN (\(Self.placeholders(count: batch.count)))
                """
            )
            try bind(batch, to: statement)

            while try statement.step() {
                guard let keyDigest = statement.columnString(0),
                      let row = rowsByDigest[keyDigest],
                      let key = keysByDigest[keyDigest],
                      let id = statement.columnString(2),
                      let roleRaw = statement.columnString(3),
                      let role = SessionTranscriptMessage.Role(rawValue: roleRaw),
                      let excerpt = statement.columnString(4) else {
                    continue
                }
                let timestampSeconds = statement.columnDouble(5)
                let timestamp = statement.columnIsNull(5)
                    ? nil
                    : Date(timeIntervalSince1970: timestampSeconds)
                examplesByDigest[keyDigest, default: [:]][statement.columnInt(1)] = TranscriptTermExample(
                    id: id,
                    sessionID: key.sessionID,
                    sessionTitle: row.sessionTitle,
                    projectName: row.projectName,
                    role: role,
                    excerpt: excerpt,
                    timestamp: timestamp
                )
            }
        }
        return examplesByDigest
    }

    private func insertSessionRow(
        key: TranscriptAnalysisKey,
        status: RowStatus,
        sessionTitle: String,
        projectName: String,
        termCount: Int,
        savedAt: TimeInterval,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO session_analysis (
                key_digest, cache_schema_version, extractor_version, tokenizer_id, dictionary_version,
                options_digest, provider, session_id, file_path_hash, file_size, last_modified_ns,
                status, session_title, project_name, term_count, saved_at, last_accessed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try statement.bind(key.digest, at: 1)
        try statement.bind(key.schemaVersion, at: 2)
        try statement.bind(key.extractorVersion, at: 3)
        try statement.bind(key.tokenizerID, at: 4)
        try statement.bind(key.analysisVersion, at: 5)
        try statement.bind(key.optionsDigest, at: 6)
        try statement.bind(key.provider.rawValue, at: 7)
        try statement.bind(key.sessionID, at: 8)
        try statement.bind(key.filePathHash, at: 9)
        try statement.bind(key.fileSize, at: 10)
        try statement.bind(key.lastModifiedNanoseconds, at: 11)
        try statement.bind(status.rawValue, at: 12)
        try statement.bind(sessionTitle, at: 13)
        try statement.bind(projectName, at: 14)
        try statement.bind(termCount, at: 15)
        try statement.bind(savedAt, at: 16)
        try statement.bind(savedAt, at: 17)
        try statement.finish()
    }

    private func insertTerm(
        _ term: TranscriptSessionTerm,
        ordinal: Int,
        keyDigest: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO session_terms (
                key_digest, ordinal, canonical, canonical_normalized, display_name, kind,
                frequency, weight, role_user, role_assistant, role_tool, role_system,
                source_dictionary, source_natural_language, source_jieba, source_code,
                source_path, source_command, source_error, source_project
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try statement.bind(keyDigest, at: 1)
        try statement.bind(ordinal, at: 2)
        try statement.bind(term.canonical, at: 3)
        try statement.bind(TermNormalizer.normalizedKey(term.canonical), at: 4)
        try statement.bind(term.displayName, at: 5)
        try statement.bind(term.kind.rawValue, at: 6)
        try statement.bind(term.frequency, at: 7)
        try statement.bind(term.weight, at: 8)
        try statement.bind(term.roleCounts.user, at: 9)
        try statement.bind(term.roleCounts.assistant, at: 10)
        try statement.bind(term.roleCounts.tool, at: 11)
        try statement.bind(term.roleCounts.system, at: 12)
        try statement.bind(0, at: 13)
        try statement.bind(term.sourceCounts.naturalLanguage, at: 14)
        try statement.bind(term.sourceCounts.jieba, at: 15)
        try statement.bind(term.sourceCounts.code, at: 16)
        try statement.bind(term.sourceCounts.path, at: 17)
        try statement.bind(term.sourceCounts.command, at: 18)
        try statement.bind(term.sourceCounts.error, at: 19)
        try statement.bind(term.sourceCounts.project, at: 20)
        try statement.finish()

        if let example = term.example {
            try insertExample(example, ordinal: ordinal, keyDigest: keyDigest, connection: connection)
        }
    }

    private func insertExample(
        _ example: TranscriptTermExample,
        ordinal: Int,
        keyDigest: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO term_examples (
                key_digest, term_ordinal, id, role, excerpt, timestamp_seconds
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        try statement.bind(keyDigest, at: 1)
        try statement.bind(ordinal, at: 2)
        try statement.bind(example.id, at: 3)
        try statement.bind(example.role.rawValue, at: 4)
        try statement.bind(example.excerpt, at: 5)
        try statement.bind(example.timestamp?.timeIntervalSince1970, at: 6)
        try statement.finish()
    }

    private func activeAnalyzedMembers(
        sessions: [Session],
        keysBySessionID: [String: TranscriptAnalysisKey],
        connection: SQLiteConnection
    ) throws -> [CorpusMember] {
        let candidates = sessions.enumerated().compactMap { ordinal, session -> CorpusMember? in
            guard let key = keysBySessionID[session.id] else { return nil }
            return CorpusMember(sessionID: session.id, keyDigest: key.digest, ordinal: ordinal)
        }
        let rowsByDigest = try cachedSessionRows(
            for: candidates.map(\.keyDigest),
            connection: connection
        )
        return candidates.filter { member in
            rowsByDigest[member.keyDigest]?.status == .analyzed
        }
    }

    private func reconcileCorpusMembers(
        scopeDigest: String,
        activeMembers: [CorpusMember],
        connection: SQLiteConnection
    ) throws {
        let existingBySessionID = try readCorpusMembers(scopeDigest: scopeDigest, connection: connection)
        let activeBySessionID = Dictionary(uniqueKeysWithValues: activeMembers.map { ($0.sessionID, $0) })
        var affectedTerms: Set<CorpusTermKey> = []

        for existing in existingBySessionID.values {
            guard let active = activeBySessionID[existing.sessionID],
                  active.keyDigest == existing.keyDigest else {
                affectedTerms.formUnion(try applyCorpusDelta(
                    scopeDigest: scopeDigest,
                    keyDigest: existing.keyDigest,
                    direction: .subtract,
                    connection: connection
                ))
                try deleteCorpusMember(scopeDigest: scopeDigest, sessionID: existing.sessionID, connection: connection)
                continue
            }

            if active.ordinal != existing.ordinal {
                try updateCorpusMemberOrdinal(active, scopeDigest: scopeDigest, connection: connection)
                affectedTerms.formUnion(try termKeys(for: active.keyDigest, connection: connection))
            }
        }

        for active in activeMembers {
            guard existingBySessionID[active.sessionID]?.keyDigest != active.keyDigest else { continue }
            affectedTerms.formUnion(try applyCorpusDelta(
                scopeDigest: scopeDigest,
                keyDigest: active.keyDigest,
                direction: .add,
                connection: connection
            ))
            try insertCorpusMember(active, scopeDigest: scopeDigest, connection: connection)
        }

        for termKey in affectedTerms {
            try rebuildCorpusPresentation(
                scopeDigest: scopeDigest,
                termKey: termKey,
                connection: connection
            )
        }
    }

    private func readCorpusMembers(
        scopeDigest: String,
        connection: SQLiteConnection
    ) throws -> [String: CorpusMember] {
        let statement = try connection.prepare(
            """
            SELECT session_id, key_digest, ordinal
            FROM corpus_members
            WHERE scope_digest = ?
            """
        )
        try statement.bind(scopeDigest, at: 1)
        var members: [String: CorpusMember] = [:]
        while try statement.step() {
            guard let sessionID = statement.columnString(0),
                  let keyDigest = statement.columnString(1) else {
                continue
            }
            members[sessionID] = CorpusMember(
                sessionID: sessionID,
                keyDigest: keyDigest,
                ordinal: statement.columnInt(2)
            )
        }
        return members
    }

    private func insertCorpusMember(
        _ member: CorpusMember,
        scopeDigest: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT OR REPLACE INTO corpus_members (scope_digest, session_id, key_digest, ordinal)
            VALUES (?, ?, ?, ?)
            """
        )
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(member.sessionID, at: 2)
        try statement.bind(member.keyDigest, at: 3)
        try statement.bind(member.ordinal, at: 4)
        try statement.finish()
    }

    private func updateCorpusMemberOrdinal(
        _ member: CorpusMember,
        scopeDigest: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            UPDATE corpus_members
            SET ordinal = ?
            WHERE scope_digest = ? AND session_id = ?
            """
        )
        try statement.bind(member.ordinal, at: 1)
        try statement.bind(scopeDigest, at: 2)
        try statement.bind(member.sessionID, at: 3)
        try statement.finish()
    }

    private func deleteCorpusMember(
        scopeDigest: String,
        sessionID: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            "DELETE FROM corpus_members WHERE scope_digest = ? AND session_id = ?"
        )
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(sessionID, at: 2)
        try statement.finish()
    }

    private func applyCorpusDelta(
        scopeDigest: String,
        keyDigest: String,
        direction: CorpusDeltaDirection,
        connection: SQLiteConnection
    ) throws -> Set<CorpusTermKey> {
        let contributions = try termContributions(for: keyDigest, connection: connection)
        for contribution in contributions {
            try applyCorpusDelta(
                scopeDigest: scopeDigest,
                contribution: contribution,
                direction: direction,
                connection: connection
            )
        }
        return Set(contributions.map(\.termKey))
    }

    private func termKeys(for keyDigest: String, connection: SQLiteConnection) throws -> Set<CorpusTermKey> {
        Set(try termContributions(for: keyDigest, connection: connection).map(\.termKey))
    }

    private func termContributions(
        for keyDigest: String,
        connection: SQLiteConnection
    ) throws -> [CorpusTermContribution] {
        let statement = try connection.prepare(
            """
            SELECT canonical, canonical_normalized, display_name, kind, frequency, weight,
                   role_user, role_assistant, role_tool, role_system,
                   source_dictionary, source_natural_language, source_jieba, source_code,
                   source_path, source_command, source_error, source_project
            FROM session_terms
            WHERE key_digest = ?
            ORDER BY ordinal ASC
            """
        )
        try statement.bind(keyDigest, at: 1)

        var contributions: [CorpusTermContribution] = []
        while try statement.step() {
            guard let canonical = statement.columnString(0),
                  let canonicalNormalized = statement.columnString(1),
                  let displayName = statement.columnString(2),
                  let kindRaw = statement.columnString(3),
                  let kind = TranscriptTermKind(rawValue: kindRaw) else {
                continue
            }
            contributions.append(CorpusTermContribution(
                canonical: canonical,
                canonicalNormalized: canonicalNormalized,
                displayName: displayName,
                kind: kind,
                frequency: statement.columnInt(4),
                weight: statement.columnDouble(5),
                roleCounts: TranscriptRoleCounts(
                    user: statement.columnInt(6),
                    assistant: statement.columnInt(7),
                    tool: statement.columnInt(8),
                    system: statement.columnInt(9)
                ),
                sourceCounts: TranscriptSourceCounts(
                    naturalLanguage: statement.columnInt(11),
                    jieba: statement.columnInt(12),
                    code: statement.columnInt(13),
                    path: statement.columnInt(14),
                    command: statement.columnInt(15),
                    error: statement.columnInt(16),
                    project: statement.columnInt(17)
                )
            ))
        }
        return contributions
    }

    private func applyCorpusDelta(
        scopeDigest: String,
        contribution: CorpusTermContribution,
        direction: CorpusDeltaDirection,
        connection: SQLiteConnection
    ) throws {
        switch direction {
        case .add:
            let statement = try connection.prepare(
                """
                INSERT INTO corpus_terms (
                    scope_digest, kind, canonical_normalized, canonical, display_name,
                    frequency, document_frequency, weight_sum,
                    role_user, role_assistant, role_tool, role_system,
                    source_dictionary, source_natural_language, source_jieba, source_code,
                    source_path, source_command, source_error, source_project
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(scope_digest, kind, canonical_normalized) DO UPDATE SET
                    frequency = frequency + excluded.frequency,
                    document_frequency = document_frequency + excluded.document_frequency,
                    weight_sum = weight_sum + excluded.weight_sum,
                    role_user = role_user + excluded.role_user,
                    role_assistant = role_assistant + excluded.role_assistant,
                    role_tool = role_tool + excluded.role_tool,
                    role_system = role_system + excluded.role_system,
                    source_dictionary = source_dictionary + excluded.source_dictionary,
                    source_natural_language = source_natural_language + excluded.source_natural_language,
                    source_jieba = source_jieba + excluded.source_jieba,
                    source_code = source_code + excluded.source_code,
                    source_path = source_path + excluded.source_path,
                    source_command = source_command + excluded.source_command,
                    source_error = source_error + excluded.source_error,
                    source_project = source_project + excluded.source_project
                """
            )
            try bindCorpusInsert(
                scopeDigest: scopeDigest,
                contribution: contribution,
                statement: statement
            )
            try statement.finish()

        case .subtract:
            let statement = try connection.prepare(
                """
                UPDATE corpus_terms
                SET frequency = frequency - ?,
                    document_frequency = document_frequency - 1,
                    weight_sum = weight_sum - ?,
                    role_user = role_user - ?,
                    role_assistant = role_assistant - ?,
                    role_tool = role_tool - ?,
                    role_system = role_system - ?,
                    source_dictionary = source_dictionary - ?,
                    source_natural_language = source_natural_language - ?,
                    source_jieba = source_jieba - ?,
                    source_code = source_code - ?,
                    source_path = source_path - ?,
                    source_command = source_command - ?,
                    source_error = source_error - ?,
                    source_project = source_project - ?
                WHERE scope_digest = ? AND kind = ? AND canonical_normalized = ?
                """
            )
            try statement.bind(contribution.frequency, at: 1)
            try statement.bind(contribution.weight, at: 2)
            try statement.bind(contribution.roleCounts.user, at: 3)
            try statement.bind(contribution.roleCounts.assistant, at: 4)
            try statement.bind(contribution.roleCounts.tool, at: 5)
            try statement.bind(contribution.roleCounts.system, at: 6)
            try statement.bind(0, at: 7)
            try statement.bind(contribution.sourceCounts.naturalLanguage, at: 8)
            try statement.bind(contribution.sourceCounts.jieba, at: 9)
            try statement.bind(contribution.sourceCounts.code, at: 10)
            try statement.bind(contribution.sourceCounts.path, at: 11)
            try statement.bind(contribution.sourceCounts.command, at: 12)
            try statement.bind(contribution.sourceCounts.error, at: 13)
            try statement.bind(contribution.sourceCounts.project, at: 14)
            try statement.bind(scopeDigest, at: 15)
            try statement.bind(contribution.kind.rawValue, at: 16)
            try statement.bind(contribution.canonicalNormalized, at: 17)
            try statement.finish()

            let cleanup = try connection.prepare(
                """
                DELETE FROM corpus_terms
                WHERE scope_digest = ? AND kind = ? AND canonical_normalized = ?
                  AND (frequency <= 0 OR document_frequency <= 0)
                """
            )
            try cleanup.bind(scopeDigest, at: 1)
            try cleanup.bind(contribution.kind.rawValue, at: 2)
            try cleanup.bind(contribution.canonicalNormalized, at: 3)
            try cleanup.finish()
        }
    }

    private func bindCorpusInsert(
        scopeDigest: String,
        contribution: CorpusTermContribution,
        statement: SQLiteStatement
    ) throws {
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(contribution.kind.rawValue, at: 2)
        try statement.bind(contribution.canonicalNormalized, at: 3)
        try statement.bind(contribution.canonical, at: 4)
        try statement.bind(contribution.displayName, at: 5)
        try statement.bind(contribution.frequency, at: 6)
        try statement.bind(1, at: 7)
        try statement.bind(contribution.weight, at: 8)
        try statement.bind(contribution.roleCounts.user, at: 9)
        try statement.bind(contribution.roleCounts.assistant, at: 10)
        try statement.bind(contribution.roleCounts.tool, at: 11)
        try statement.bind(contribution.roleCounts.system, at: 12)
        try statement.bind(0, at: 13)
        try statement.bind(contribution.sourceCounts.naturalLanguage, at: 14)
        try statement.bind(contribution.sourceCounts.jieba, at: 15)
        try statement.bind(contribution.sourceCounts.code, at: 16)
        try statement.bind(contribution.sourceCounts.path, at: 17)
        try statement.bind(contribution.sourceCounts.command, at: 18)
        try statement.bind(contribution.sourceCounts.error, at: 19)
        try statement.bind(contribution.sourceCounts.project, at: 20)
    }

    private func rebuildCorpusPresentation(
        scopeDigest: String,
        termKey: CorpusTermKey,
        connection: SQLiteConnection
    ) throws {
        try deleteCorpusPresentation(scopeDigest: scopeDigest, termKey: termKey, connection: connection)
        guard let presentation = try corpusPresentation(
            scopeDigest: scopeDigest,
            termKey: termKey,
            connection: connection
        ) else {
            return
        }

        let update = try connection.prepare(
            """
            UPDATE corpus_terms
            SET canonical = ?, display_name = ?
            WHERE scope_digest = ? AND kind = ? AND canonical_normalized = ?
            """
        )
        try update.bind(presentation.canonical, at: 1)
        try update.bind(presentation.displayName, at: 2)
        try update.bind(scopeDigest, at: 3)
        try update.bind(termKey.kind.rawValue, at: 4)
        try update.bind(termKey.canonicalNormalized, at: 5)
        try update.finish()

        for (alias, count) in presentation.aliasCounts.sorted(by: { $0.key < $1.key }) {
            guard alias != presentation.displayName else { continue }
            let insert = try connection.prepare(
                """
                INSERT INTO corpus_term_aliases (
                    scope_digest, kind, canonical_normalized, alias, count
                ) VALUES (?, ?, ?, ?, ?)
                """
            )
            try insert.bind(scopeDigest, at: 1)
            try insert.bind(termKey.kind.rawValue, at: 2)
            try insert.bind(termKey.canonicalNormalized, at: 3)
            try insert.bind(alias, at: 4)
            try insert.bind(count, at: 5)
            try insert.finish()
        }

        for (ordinal, example) in presentation.examples.enumerated() {
            let insert = try connection.prepare(
                """
                INSERT INTO corpus_term_examples (
                    scope_digest, kind, canonical_normalized, ordinal, id,
                    session_id, session_title, project_name, role, excerpt, timestamp_seconds
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            try insert.bind(scopeDigest, at: 1)
            try insert.bind(termKey.kind.rawValue, at: 2)
            try insert.bind(termKey.canonicalNormalized, at: 3)
            try insert.bind(ordinal, at: 4)
            try insert.bind(example.id, at: 5)
            try insert.bind(example.sessionID, at: 6)
            try insert.bind(example.sessionTitle, at: 7)
            try insert.bind(example.projectName, at: 8)
            try insert.bind(example.role.rawValue, at: 9)
            try insert.bind(example.excerpt, at: 10)
            try insert.bind(example.timestamp?.timeIntervalSince1970, at: 11)
            try insert.finish()
        }
    }

    private func deleteCorpusPresentation(
        scopeDigest: String,
        termKey: CorpusTermKey,
        connection: SQLiteConnection
    ) throws {
        let aliases = try connection.prepare(
            """
            DELETE FROM corpus_term_aliases
            WHERE scope_digest = ? AND kind = ? AND canonical_normalized = ?
            """
        )
        try aliases.bind(scopeDigest, at: 1)
        try aliases.bind(termKey.kind.rawValue, at: 2)
        try aliases.bind(termKey.canonicalNormalized, at: 3)
        try aliases.finish()

        let examples = try connection.prepare(
            """
            DELETE FROM corpus_term_examples
            WHERE scope_digest = ? AND kind = ? AND canonical_normalized = ?
            """
        )
        try examples.bind(scopeDigest, at: 1)
        try examples.bind(termKey.kind.rawValue, at: 2)
        try examples.bind(termKey.canonicalNormalized, at: 3)
        try examples.finish()
    }

    private func corpusPresentation(
        scopeDigest: String,
        termKey: CorpusTermKey,
        connection: SQLiteConnection
    ) throws -> CorpusTermPresentation? {
        let statement = try connection.prepare(
            """
            SELECT st.canonical, st.display_name
            FROM session_terms st
            INNER JOIN corpus_members cm
                ON cm.key_digest = st.key_digest AND cm.scope_digest = ?
            WHERE st.kind = ? AND st.canonical_normalized = ?
            ORDER BY cm.ordinal ASC, st.ordinal ASC
            """
        )
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(termKey.kind.rawValue, at: 2)
        try statement.bind(termKey.canonicalNormalized, at: 3)

        var canonical: String?
        var displayName: String?
        var aliasCounts: [String: Int] = [:]
        while try statement.step() {
            guard let rowCanonical = statement.columnString(0),
                  let rowDisplayName = statement.columnString(1) else {
                continue
            }
            canonical = canonical ?? rowCanonical
            displayName = displayName ?? rowDisplayName
            aliasCounts[rowDisplayName, default: 0] += 1
        }
        guard let canonical, let displayName else { return nil }

        return CorpusTermPresentation(
            canonical: canonical,
            displayName: displayName,
            aliasCounts: aliasCounts,
            examples: try corpusExamples(scopeDigest: scopeDigest, termKey: termKey, connection: connection)
        )
    }

    private func corpusExamples(
        scopeDigest: String,
        termKey: CorpusTermKey,
        connection: SQLiteConnection
    ) throws -> [TranscriptTermExample] {
        let statement = try connection.prepare(
            """
            SELECT te.id, sa.session_id, sa.session_title, sa.project_name,
                   te.role, te.excerpt, te.timestamp_seconds
            FROM session_terms st
            INNER JOIN corpus_members cm
                ON cm.key_digest = st.key_digest AND cm.scope_digest = ?
            INNER JOIN session_analysis sa
                ON sa.key_digest = st.key_digest
            INNER JOIN term_examples te
                ON te.key_digest = st.key_digest AND te.term_ordinal = st.ordinal
            WHERE st.kind = ? AND st.canonical_normalized = ?
            ORDER BY cm.ordinal ASC, st.ordinal ASC
            LIMIT 3
            """
        )
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(termKey.kind.rawValue, at: 2)
        try statement.bind(termKey.canonicalNormalized, at: 3)

        var examples: [TranscriptTermExample] = []
        while try statement.step() {
            guard let id = statement.columnString(0),
                  let sessionID = statement.columnString(1),
                  let sessionTitle = statement.columnString(2),
                  let projectName = statement.columnString(3),
                  let roleRaw = statement.columnString(4),
                  let role = SessionTranscriptMessage.Role(rawValue: roleRaw),
                  let excerpt = statement.columnString(5) else {
                continue
            }
            let timestamp = statement.columnIsNull(6)
                ? nil
                : Date(timeIntervalSince1970: statement.columnDouble(6))
            examples.append(TranscriptTermExample(
                id: id,
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                projectName: projectName,
                role: role,
                excerpt: excerpt,
                timestamp: timestamp
            ))
        }
        return examples
    }

    private func readCorpusTerms(
        scopeDigest: String,
        documentCount: Int,
        connection: SQLiteConnection
    ) throws -> [TranscriptTermStats] {
        let aliases = try readCorpusAliases(scopeDigest: scopeDigest, connection: connection)
        let examples = try readCorpusExamples(scopeDigest: scopeDigest, connection: connection)
        let statement = try connection.prepare(
            """
            SELECT kind, canonical_normalized, canonical, display_name, frequency,
                   document_frequency, weight_sum,
                   role_user, role_assistant, role_tool, role_system,
                   source_dictionary, source_natural_language, source_jieba, source_code,
                   source_path, source_command, source_error, source_project
            FROM corpus_terms
            WHERE scope_digest = ?
            """
        )
        try statement.bind(scopeDigest, at: 1)

        var terms: [TranscriptTermStats] = []
        while try statement.step() {
            guard let kindRaw = statement.columnString(0),
                  let kind = TranscriptTermKind(rawValue: kindRaw),
                  let canonicalNormalized = statement.columnString(1),
                  let canonical = statement.columnString(2),
                  let displayName = statement.columnString(3) else {
                continue
            }
            let key = CorpusTermKey(kind: kind, canonicalNormalized: canonicalNormalized)
            let frequency = statement.columnInt(4)
            let df = max(statement.columnInt(5), 1)
            let idf = log((Double(documentCount) + 1.0) / (Double(df) + 1.0)) + 1.0
            let weight = statement.columnDouble(6) / Double(max(df, 1))
            terms.append(TranscriptTermStats(
                canonical: canonical,
                displayName: displayName,
                kind: kind,
                aliases: aliases[key, default: []].filter { $0 != displayName }.sorted(),
                frequency: frequency,
                documentFrequency: df,
                tfidf: Double(frequency) * idf * Self.boost(for: kind) * max(weight, 0.8),
                roleCounts: TranscriptRoleCounts(
                    user: statement.columnInt(7),
                    assistant: statement.columnInt(8),
                    tool: statement.columnInt(9),
                    system: statement.columnInt(10)
                ),
                sourceCounts: TranscriptSourceCounts(
                    naturalLanguage: statement.columnInt(12),
                    jieba: statement.columnInt(13),
                    code: statement.columnInt(14),
                    path: statement.columnInt(15),
                    command: statement.columnInt(16),
                    error: statement.columnInt(17),
                    project: statement.columnInt(18)
                ),
                examples: examples[key, default: []]
            ))
        }

        return terms.sorted {
            if $0.tfidf != $1.tfidf { return $0.tfidf > $1.tfidf }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func readCorpusAliases(
        scopeDigest: String,
        connection: SQLiteConnection
    ) throws -> [CorpusTermKey: [String]] {
        let statement = try connection.prepare(
            """
            SELECT kind, canonical_normalized, alias
            FROM corpus_term_aliases
            WHERE scope_digest = ?
            """
        )
        try statement.bind(scopeDigest, at: 1)
        var aliases: [CorpusTermKey: Set<String>] = [:]
        while try statement.step() {
            guard let kindRaw = statement.columnString(0),
                  let kind = TranscriptTermKind(rawValue: kindRaw),
                  let canonicalNormalized = statement.columnString(1),
                  let alias = statement.columnString(2) else {
                continue
            }
            aliases[CorpusTermKey(kind: kind, canonicalNormalized: canonicalNormalized), default: []].insert(alias)
        }
        return aliases.mapValues { Array($0) }
    }

    private func readCorpusExamples(
        scopeDigest: String,
        connection: SQLiteConnection
    ) throws -> [CorpusTermKey: [TranscriptTermExample]] {
        let statement = try connection.prepare(
            """
            SELECT kind, canonical_normalized, id, session_id, session_title,
                   project_name, role, excerpt, timestamp_seconds
            FROM corpus_term_examples
            WHERE scope_digest = ?
            ORDER BY kind ASC, canonical_normalized ASC, ordinal ASC
            """
        )
        try statement.bind(scopeDigest, at: 1)
        var examples: [CorpusTermKey: [TranscriptTermExample]] = [:]
        while try statement.step() {
            guard let kindRaw = statement.columnString(0),
                  let kind = TranscriptTermKind(rawValue: kindRaw),
                  let canonicalNormalized = statement.columnString(1),
                  let id = statement.columnString(2),
                  let sessionID = statement.columnString(3),
                  let sessionTitle = statement.columnString(4),
                  let projectName = statement.columnString(5),
                  let roleRaw = statement.columnString(6),
                  let role = SessionTranscriptMessage.Role(rawValue: roleRaw),
                  let excerpt = statement.columnString(7) else {
                continue
            }
            let timestamp = statement.columnIsNull(8)
                ? nil
                : Date(timeIntervalSince1970: statement.columnDouble(8))
            let key = CorpusTermKey(kind: kind, canonicalNormalized: canonicalNormalized)
            examples[key, default: []].append(TranscriptTermExample(
                id: id,
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                projectName: projectName,
                role: role,
                excerpt: excerpt,
                timestamp: timestamp
            ))
        }
        return examples
    }

    private func upsertCorpusState(
        scopeDigest: String,
        provider: ProviderKind,
        extractorVersion: String,
        tokenizerID: String,
        optionsDigest: String,
        sessionSetDigest: String,
        analysisSignature: String,
        sessionCount: Int,
        analyzedSessionCount: Int,
        updatedAt: TimeInterval,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO corpus_state (
                scope_digest, provider, extractor_version, tokenizer_id, options_digest,
                session_set_digest, dictionary_signature, session_count,
                analyzed_session_count, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(scope_digest) DO UPDATE SET
                provider = excluded.provider,
                extractor_version = excluded.extractor_version,
                tokenizer_id = excluded.tokenizer_id,
                options_digest = excluded.options_digest,
                session_set_digest = excluded.session_set_digest,
                dictionary_signature = excluded.dictionary_signature,
                session_count = excluded.session_count,
                analyzed_session_count = excluded.analyzed_session_count,
                updated_at = excluded.updated_at
            """
        )
        try statement.bind(scopeDigest, at: 1)
        try statement.bind(provider.rawValue, at: 2)
        try statement.bind(extractorVersion, at: 3)
        try statement.bind(tokenizerID, at: 4)
        try statement.bind(optionsDigest, at: 5)
        try statement.bind(sessionSetDigest, at: 6)
        try statement.bind(analysisSignature, at: 7)
        try statement.bind(sessionCount, at: 8)
        try statement.bind(analyzedSessionCount, at: 9)
        try statement.bind(updatedAt, at: 10)
        try statement.finish()
    }

    private func detachMaterializedMembers(
        keyDigest: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            SELECT cm.scope_digest, cm.session_id, sa.term_count
            FROM corpus_members cm
            LEFT JOIN session_analysis sa ON sa.key_digest = cm.key_digest
            WHERE cm.key_digest = ?
            """
        )
        try statement.bind(keyDigest, at: 1)
        var memberships: [(scopeDigest: String, sessionID: String, termCount: Int)] = []
        while try statement.step() {
            guard let scopeDigest = statement.columnString(0),
                  let sessionID = statement.columnString(1) else {
                continue
            }
            memberships.append((scopeDigest, sessionID, statement.columnInt(2)))
        }
        try detachMaterializedMemberships(memberships, keyDigest: keyDigest, connection: connection)
    }

    private func detachMaterializedMembers(
        provider: ProviderKind,
        sessionID: String,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            SELECT cm.scope_digest, cm.key_digest, sa.term_count
            FROM corpus_members cm
            INNER JOIN corpus_state cs ON cs.scope_digest = cm.scope_digest
            LEFT JOIN session_analysis sa ON sa.key_digest = cm.key_digest
            WHERE cs.provider = ? AND cm.session_id = ?
            """
        )
        try statement.bind(provider.rawValue, at: 1)
        try statement.bind(sessionID, at: 2)
        var rows: [(scopeDigest: String, keyDigest: String, termCount: Int)] = []
        while try statement.step() {
            guard let scopeDigest = statement.columnString(0),
                  let keyDigest = statement.columnString(1) else {
                continue
            }
            rows.append((scopeDigest, keyDigest, statement.columnInt(2)))
        }
        for row in rows {
            try detachMaterializedMemberships(
                [(scopeDigest: row.scopeDigest, sessionID: sessionID, termCount: row.termCount)],
                keyDigest: row.keyDigest,
                connection: connection
            )
        }
    }

    private func detachMaterializedMemberships(
        _ memberships: [(scopeDigest: String, sessionID: String, termCount: Int)],
        keyDigest: String,
        connection: SQLiteConnection
    ) throws {
        guard !memberships.isEmpty else { return }
        let contributions = try termContributions(for: keyDigest, connection: connection)
        for membership in memberships {
            if contributions.isEmpty, membership.termCount > 0 {
                try resetMaterializedScope(scopeDigest: membership.scopeDigest, connection: connection)
                continue
            }
            var affectedTerms: Set<CorpusTermKey> = []
            for contribution in contributions {
                try applyCorpusDelta(
                    scopeDigest: membership.scopeDigest,
                    contribution: contribution,
                    direction: .subtract,
                    connection: connection
                )
                affectedTerms.insert(contribution.termKey)
            }
            try deleteCorpusMember(
                scopeDigest: membership.scopeDigest,
                sessionID: membership.sessionID,
                connection: connection
            )
            for termKey in affectedTerms {
                try rebuildCorpusPresentation(
                    scopeDigest: membership.scopeDigest,
                    termKey: termKey,
                    connection: connection
                )
            }
        }
    }

    private func resetMaterializedScope(scopeDigest: String, connection: SQLiteConnection) throws {
        for table in ["corpus_term_examples", "corpus_term_aliases", "corpus_terms", "corpus_members", "corpus_state"] {
            let statement = try connection.prepare("DELETE FROM \(table) WHERE scope_digest = ?")
            try statement.bind(scopeDigest, at: 1)
            try statement.finish()
        }
    }

    private func priorSessionIDs(
        provider: ProviderKind,
        sessionIDs: Set<String>,
        connection: SQLiteConnection
    ) throws -> Set<String> {
        var prior: Set<String> = []
        for batch in Self.batches(of: Array(sessionIDs)) {
            let statement = try connection.prepare(
                """
                SELECT DISTINCT session_id
                FROM session_analysis
                WHERE provider = ? AND session_id IN (\(Self.placeholders(count: batch.count)))
                """
            )
            try statement.bind(provider.rawValue, at: 1)
            try bind(batch, to: statement, startingAt: 2)

            while try statement.step() {
                if let sessionID = statement.columnString(0) {
                    prior.insert(sessionID)
                }
            }
        }
        return prior
    }

    private func touch(keyDigests: [String], connection: SQLiteConnection) throws {
        let accessedAt = Date().timeIntervalSince1970
        for batch in Self.batches(of: keyDigests) {
            let statement = try connection.prepare(
                """
                UPDATE session_analysis
                SET last_accessed_at = ?
                WHERE key_digest IN (\(Self.placeholders(count: batch.count)))
                """
            )
            try statement.bind(accessedAt, at: 1)
            try bind(batch, to: statement, startingAt: 2)
            try statement.finish()
        }
    }

    private func delete(keyDigest: String, connection: SQLiteConnection) throws {
        try detachMaterializedMembers(keyDigest: keyDigest, connection: connection)
        let statement = try connection.prepare("DELETE FROM session_analysis WHERE key_digest = ?")
        try statement.bind(keyDigest, at: 1)
        try statement.finish()
    }

    private func delete(provider: ProviderKind, sessionID: String, connection: SQLiteConnection) throws {
        try detachMaterializedMembers(provider: provider, sessionID: sessionID, connection: connection)
        let statement = try connection.prepare("DELETE FROM session_analysis WHERE provider = ? AND session_id = ?")
        try statement.bind(provider.rawValue, at: 1)
        try statement.bind(sessionID, at: 2)
        try statement.finish()
    }

    private static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return base
            .appendingPathComponent("com.claudestats.ClaudeStats", isDirectory: true)
            .appendingPathComponent("TranscriptAnalysis", isDirectory: true)
            .appendingPathComponent("index.sqlite3")
    }

    private static func lastModifiedNanoseconds(for session: Session) -> Int64 {
        Int64((session.lastModified.timeIntervalSince1970 * 1_000_000_000).rounded())
    }

    private static func corpusScopeDigest(
        provider: ProviderKind,
        schemaVersion: Int,
        extractorVersion: String,
        tokenizerID: String,
        optionsDigest: String
    ) -> String {
        sha256([
            provider.rawValue,
            "\(schemaVersion)",
            extractorVersion,
            tokenizerID,
            optionsDigest,
        ].joined(separator: "|"))
    }

    private static func sessionSetDigest(for members: [CorpusMember]) -> String {
        sha256(
            members
                .map { "\($0.sessionID):\($0.keyDigest):\($0.ordinal)" }
                .sorted()
                .joined(separator: "|")
        )
    }

    private static func boost(for kind: TranscriptTermKind) -> Double {
        switch kind {
        case .filePath, .command, .error: 1.45
        case .framework, .api, .typeName, .configKey: 1.25
        case .language, .workflow: 1.15
        case .function: 1.2
        case .general: 1.0
        }
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func bind(_ values: [String], to statement: SQLiteStatement, startingAt start: Int32 = 1) throws {
        for (offset, value) in values.enumerated() {
            try statement.bind(value, at: start + Int32(offset))
        }
    }

    private static func batches(of values: [String]) -> [[String]] {
        guard !values.isEmpty else { return [] }
        return stride(from: values.startIndex, to: values.endIndex, by: maxBoundParameters).map { start in
            let end = Swift.min(start + maxBoundParameters, values.endIndex)
            return Array(values[start..<end])
        }
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private enum RowStatus: String {
        case analyzed
        case empty
    }

    private struct CachedSessionRow {
        let status: RowStatus
        let sessionTitle: String
        let projectName: String
        let termCount: Int
    }

    private struct CorpusMember: Hashable, Sendable {
        let sessionID: String
        let keyDigest: String
        let ordinal: Int
    }

    private struct CorpusTermKey: Hashable, Sendable {
        let kind: TranscriptTermKind
        let canonicalNormalized: String
    }

    private struct CorpusTermContribution: Sendable {
        let canonical: String
        let canonicalNormalized: String
        let displayName: String
        let kind: TranscriptTermKind
        let frequency: Int
        let weight: Double
        let roleCounts: TranscriptRoleCounts
        let sourceCounts: TranscriptSourceCounts

        var termKey: CorpusTermKey {
            CorpusTermKey(kind: kind, canonicalNormalized: canonicalNormalized)
        }
    }

    private struct CorpusTermPresentation: Sendable {
        let canonical: String
        let displayName: String
        let aliasCounts: [String: Int]
        let examples: [TranscriptTermExample]
    }

    private enum CorpusDeltaDirection {
        case add
        case subtract
    }

    private static let maxBoundParameters = 900
}
