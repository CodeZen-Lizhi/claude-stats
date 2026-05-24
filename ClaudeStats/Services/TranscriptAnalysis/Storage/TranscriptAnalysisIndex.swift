import CryptoKit
import Foundation

struct TranscriptAnalysisKey: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let extractorVersion: String
    let tokenizerID: String
    let dictionaryVersion: String
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
            dictionaryVersion,
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
    case hit(TranscriptSessionAnalysis)
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
    static let defaultOptionsDigest = "default"

    private let url: URL
    private let schemaVersion: Int
    private var connection: SQLiteConnection?

    init(url: URL? = nil, schemaVersion: Int = TranscriptAnalysisIndexSchema.version) {
        self.url = url ?? Self.defaultDatabaseURL()
        self.schemaVersion = schemaVersion
    }

    func key(
        for session: Session,
        tokenizerID: String,
        dictionaryVersion: String,
        extractorVersion: String = TranscriptAnalysisService.extractorVersion,
        optionsDigest: String = TranscriptAnalysisIndex.defaultOptionsDigest
    ) -> TranscriptAnalysisKey {
        TranscriptAnalysisKey(
            schemaVersion: schemaVersion,
            extractorVersion: extractorVersion,
            tokenizerID: tokenizerID,
            dictionaryVersion: dictionaryVersion,
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
        dictionaryVersion: String,
        dictionaryVersionsBySessionID: [String: String] = [:],
        extractorVersion: String = TranscriptAnalysisService.extractorVersion,
        optionsDigest: String = TranscriptAnalysisIndex.defaultOptionsDigest,
        forceRefresh: Bool = false
    ) throws -> [TranscriptAnalysisLookup] {
        let connection = try openConnection()
        var out: [TranscriptAnalysisLookup] = []
        out.reserveCapacity(sessions.count)

        for session in sessions {
            let key = key(
                for: session,
                tokenizerID: tokenizerID,
                dictionaryVersion: dictionaryVersionsBySessionID[session.id] ?? dictionaryVersion,
                extractorVersion: extractorVersion,
                optionsDigest: optionsDigest
            )

            if !forceRefresh, let status = try status(for: key, connection: connection) {
                try touch(keyDigest: key.digest, connection: connection)
                switch status {
                case .analyzed:
                    if let analysis = try readAnalysis(for: key, connection: connection) {
                        out.append(TranscriptAnalysisLookup(session: session, key: key, state: .hit(analysis)))
                    } else {
                        try delete(keyDigest: key.digest, connection: connection)
                        out.append(TranscriptAnalysisLookup(session: session, key: key, state: .missChanged))
                    }
                case .empty:
                    out.append(TranscriptAnalysisLookup(session: session, key: key, state: .empty))
                }
                continue
            }

            let hadPrior = try hasPriorSession(provider: provider, sessionID: session.id, connection: connection)
            out.append(TranscriptAnalysisLookup(session: session, key: key, state: hadPrior ? .missChanged : .missNew))
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

    func removeAll() throws {
        let connection = try openConnection()
        try connection.transaction {
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

    private func status(for key: TranscriptAnalysisKey, connection: SQLiteConnection) throws -> RowStatus? {
        let statement = try connection.prepare("SELECT status FROM session_analysis WHERE key_digest = ?")
        try statement.bind(key.digest, at: 1)
        guard try statement.step(), let raw = statement.columnString(0) else { return nil }
        return RowStatus(rawValue: raw)
    }

    private func readAnalysis(for key: TranscriptAnalysisKey, connection: SQLiteConnection) throws -> TranscriptSessionAnalysis? {
        let row = try connection.prepare(
            """
            SELECT session_title, project_name, status
            FROM session_analysis
            WHERE key_digest = ?
            """
        )
        try row.bind(key.digest, at: 1)
        guard try row.step(),
              row.columnString(2) == RowStatus.analyzed.rawValue,
              let sessionTitle = row.columnString(0),
              let projectName = row.columnString(1) else {
            return nil
        }

        let examples = try readExamples(for: key.digest, sessionID: key.sessionID, sessionTitle: sessionTitle, projectName: projectName, connection: connection)
        let terms = try readTerms(for: key.digest, examples: examples, connection: connection)
        return TranscriptSessionAnalysis(
            sessionID: key.sessionID,
            sessionTitle: sessionTitle,
            projectName: projectName,
            terms: terms
        )
    }

    private func readTerms(
        for keyDigest: String,
        examples: [Int: TranscriptTermExample],
        connection: SQLiteConnection
    ) throws -> [TranscriptSessionTerm] {
        let statement = try connection.prepare(
            """
            SELECT ordinal, canonical, display_name, kind, frequency, weight,
                   role_user, role_assistant, role_tool, role_system,
                   source_dictionary, source_natural_language, source_jieba, source_code,
                   source_path, source_command, source_error, source_project
            FROM session_terms
            WHERE key_digest = ?
            ORDER BY ordinal ASC
            """
        )
        try statement.bind(keyDigest, at: 1)

        var terms: [TranscriptSessionTerm] = []
        while try statement.step() {
            let ordinal = statement.columnInt(0)
            guard let canonical = statement.columnString(1),
                  let displayName = statement.columnString(2),
                  let kindRaw = statement.columnString(3),
                  let kind = TranscriptTermKind(rawValue: kindRaw) else {
                continue
            }
            let roleCounts = TranscriptRoleCounts(
                user: statement.columnInt(6),
                assistant: statement.columnInt(7),
                tool: statement.columnInt(8),
                system: statement.columnInt(9)
            )
            let sourceCounts = TranscriptSourceCounts(
                dictionary: statement.columnInt(10),
                naturalLanguage: statement.columnInt(11),
                jieba: statement.columnInt(12),
                code: statement.columnInt(13),
                path: statement.columnInt(14),
                command: statement.columnInt(15),
                error: statement.columnInt(16),
                project: statement.columnInt(17)
            )
            terms.append(TranscriptSessionTerm(
                canonical: canonical,
                displayName: displayName,
                kind: kind,
                frequency: statement.columnInt(4),
                weight: statement.columnDouble(5),
                roleCounts: roleCounts,
                sourceCounts: sourceCounts,
                example: examples[ordinal]
            ))
        }
        return terms
    }

    private func readExamples(
        for keyDigest: String,
        sessionID: String,
        sessionTitle: String,
        projectName: String,
        connection: SQLiteConnection
    ) throws -> [Int: TranscriptTermExample] {
        let statement = try connection.prepare(
            """
            SELECT term_ordinal, id, role, excerpt, timestamp_seconds
            FROM term_examples
            WHERE key_digest = ?
            """
        )
        try statement.bind(keyDigest, at: 1)

        var examples: [Int: TranscriptTermExample] = [:]
        while try statement.step() {
            guard let id = statement.columnString(1),
                  let roleRaw = statement.columnString(2),
                  let role = SessionTranscriptMessage.Role(rawValue: roleRaw),
                  let excerpt = statement.columnString(3) else {
                continue
            }
            let timestampSeconds = statement.columnDouble(4)
            let timestamp = statement.columnIsNull(4)
                ? nil
                : Date(timeIntervalSince1970: timestampSeconds)
            examples[statement.columnInt(0)] = TranscriptTermExample(
                id: id,
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                projectName: projectName,
                role: role,
                excerpt: excerpt,
                timestamp: timestamp
            )
        }
        return examples
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
        try statement.bind(key.dictionaryVersion, at: 5)
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
        try statement.bind(TechnicalTermDictionary.normalized(term.canonical), at: 4)
        try statement.bind(term.displayName, at: 5)
        try statement.bind(term.kind.rawValue, at: 6)
        try statement.bind(term.frequency, at: 7)
        try statement.bind(term.weight, at: 8)
        try statement.bind(term.roleCounts.user, at: 9)
        try statement.bind(term.roleCounts.assistant, at: 10)
        try statement.bind(term.roleCounts.tool, at: 11)
        try statement.bind(term.roleCounts.system, at: 12)
        try statement.bind(term.sourceCounts.dictionary, at: 13)
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

    private func hasPriorSession(provider: ProviderKind, sessionID: String, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.prepare(
            "SELECT 1 FROM session_analysis WHERE provider = ? AND session_id = ? LIMIT 1"
        )
        try statement.bind(provider.rawValue, at: 1)
        try statement.bind(sessionID, at: 2)
        return try statement.step()
    }

    private func touch(keyDigest: String, connection: SQLiteConnection) throws {
        let statement = try connection.prepare(
            "UPDATE session_analysis SET last_accessed_at = ? WHERE key_digest = ?"
        )
        try statement.bind(Date().timeIntervalSince1970, at: 1)
        try statement.bind(keyDigest, at: 2)
        try statement.finish()
    }

    private func delete(keyDigest: String, connection: SQLiteConnection) throws {
        let statement = try connection.prepare("DELETE FROM session_analysis WHERE key_digest = ?")
        try statement.bind(keyDigest, at: 1)
        try statement.finish()
    }

    private func delete(provider: ProviderKind, sessionID: String, connection: SQLiteConnection) throws {
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

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum RowStatus: String {
        case analyzed
        case empty
    }
}
