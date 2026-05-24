import Foundation

enum TranscriptAnalysisIndexSchema {
    static let version = 2

    static func configure(_ connection: SQLiteConnection) throws {
        try connection.execute("PRAGMA journal_mode=WAL")
        try connection.execute("PRAGMA synchronous=NORMAL")
        try connection.execute("PRAGMA foreign_keys=ON")
        try connection.execute("PRAGMA busy_timeout=2500")
    }

    static func migrate(_ connection: SQLiteConnection) throws {
        try configure(connection)
        let userVersion = try currentUserVersion(connection)
        guard userVersion < version else { return }
        if userVersion == 0 {
            try createV1(connection)
        }
        if userVersion < 2 {
            try createV2(connection)
        }
        try connection.execute("PRAGMA user_version = \(version)")
    }

    private static func currentUserVersion(_ connection: SQLiteConnection) throws -> Int {
        let statement = try connection.prepare("PRAGMA user_version")
        defer { statement.reset() }
        guard try statement.step() else { return 0 }
        return statement.columnInt(0)
    }

    private static func createV1(_ connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS session_analysis (
                key_digest TEXT PRIMARY KEY NOT NULL,
                cache_schema_version INTEGER NOT NULL,
                extractor_version TEXT NOT NULL,
                tokenizer_id TEXT NOT NULL,
                dictionary_version TEXT NOT NULL,
                options_digest TEXT NOT NULL,
                provider TEXT NOT NULL,
                session_id TEXT NOT NULL,
                file_path_hash TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                last_modified_ns INTEGER NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('analyzed', 'empty')),
                session_title TEXT NOT NULL,
                project_name TEXT NOT NULL,
                term_count INTEGER NOT NULL,
                saved_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS session_terms (
                key_digest TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                canonical TEXT NOT NULL,
                canonical_normalized TEXT NOT NULL,
                display_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                frequency INTEGER NOT NULL,
                weight REAL NOT NULL,
                role_user INTEGER NOT NULL,
                role_assistant INTEGER NOT NULL,
                role_tool INTEGER NOT NULL,
                role_system INTEGER NOT NULL,
                source_dictionary INTEGER NOT NULL,
                source_natural_language INTEGER NOT NULL,
                source_jieba INTEGER NOT NULL,
                source_code INTEGER NOT NULL,
                source_path INTEGER NOT NULL,
                source_command INTEGER NOT NULL,
                source_error INTEGER NOT NULL,
                source_project INTEGER NOT NULL,
                PRIMARY KEY (key_digest, ordinal),
                FOREIGN KEY (key_digest) REFERENCES session_analysis(key_digest) ON DELETE CASCADE
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS term_examples (
                key_digest TEXT NOT NULL,
                term_ordinal INTEGER NOT NULL,
                id TEXT NOT NULL,
                role TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                timestamp_seconds REAL,
                PRIMARY KEY (key_digest, term_ordinal),
                FOREIGN KEY (key_digest, term_ordinal) REFERENCES session_terms(key_digest, ordinal) ON DELETE CASCADE
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_session_analysis_lookup
            ON session_analysis (
                provider,
                session_id,
                file_path_hash,
                file_size,
                last_modified_ns,
                cache_schema_version,
                extractor_version,
                tokenizer_id,
                dictionary_version,
                options_digest
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_session_analysis_provider_session
            ON session_analysis (provider, session_id);
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_session_terms_kind_canonical
            ON session_terms (kind, canonical_normalized);
            """
        )
    }

    private static func createV2(_ connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS corpus_state (
                scope_digest TEXT PRIMARY KEY NOT NULL,
                provider TEXT NOT NULL,
                extractor_version TEXT NOT NULL,
                tokenizer_id TEXT NOT NULL,
                options_digest TEXT NOT NULL,
                session_set_digest TEXT NOT NULL,
                dictionary_signature TEXT NOT NULL,
                session_count INTEGER NOT NULL,
                analyzed_session_count INTEGER NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS corpus_members (
                scope_digest TEXT NOT NULL,
                session_id TEXT NOT NULL,
                key_digest TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                PRIMARY KEY (scope_digest, session_id)
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS corpus_terms (
                scope_digest TEXT NOT NULL,
                kind TEXT NOT NULL,
                canonical_normalized TEXT NOT NULL,
                canonical TEXT NOT NULL,
                display_name TEXT NOT NULL,
                frequency INTEGER NOT NULL,
                document_frequency INTEGER NOT NULL,
                weight_sum REAL NOT NULL,
                role_user INTEGER NOT NULL,
                role_assistant INTEGER NOT NULL,
                role_tool INTEGER NOT NULL,
                role_system INTEGER NOT NULL,
                source_dictionary INTEGER NOT NULL,
                source_natural_language INTEGER NOT NULL,
                source_jieba INTEGER NOT NULL,
                source_code INTEGER NOT NULL,
                source_path INTEGER NOT NULL,
                source_command INTEGER NOT NULL,
                source_error INTEGER NOT NULL,
                source_project INTEGER NOT NULL,
                PRIMARY KEY (scope_digest, kind, canonical_normalized)
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS corpus_term_aliases (
                scope_digest TEXT NOT NULL,
                kind TEXT NOT NULL,
                canonical_normalized TEXT NOT NULL,
                alias TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY (scope_digest, kind, canonical_normalized, alias)
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS corpus_term_examples (
                scope_digest TEXT NOT NULL,
                kind TEXT NOT NULL,
                canonical_normalized TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                session_title TEXT NOT NULL,
                project_name TEXT NOT NULL,
                role TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                timestamp_seconds REAL,
                PRIMARY KEY (scope_digest, kind, canonical_normalized, ordinal)
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_corpus_members_key_digest
            ON corpus_members (key_digest);
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_corpus_terms_scope_score
            ON corpus_terms (scope_digest, document_frequency, frequency);
            """
        )
    }
}
