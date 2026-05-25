import Foundation
import Observation
import Testing
@testable import ClaudeStats

@Suite("Jieba tokenizer")
struct JiebaTokenizerTests {
    @Test("Chinese tokenizer uses bundled CppJieba dictionaries and custom words")
    func bundledJiebaAndCustomWords() async {
        let tokenizer = JiebaTokenizer()
        #expect(await tokenizer.isAvailable)

        await tokenizer.insertUserWords(["语义分析"])
        let precise = await tokenizer.cut("我们要做语义分析和词云")
        let search = await tokenizer.cut("我们要做语义分析和词云", forSearch: true)
        let tokens = precise + search

        #expect(tokens.contains("语义分析"))
        #expect(tokens.contains("词云") || tokens.contains { $0.contains("词云") })
        #expect(tokens.allSatisfy { !$0.isEmpty })
    }
}

@Suite("Transcript term extractor")
struct TranscriptTermExtractorTests {
    @Test("Extracts mixed Chinese English code paths commands and errors")
    func extractsMixedTranscriptTerms() async throws {
        let session = Self.session(id: "claude::analysis", provider: .claude)
        let messages = [
            Self.message(
                role: .user,
                text: "请分析 SessionStore 和 SwiftUI。运行 `bash scripts/run-debug.sh` 后遇到 build failed，路径 ClaudeStats/Views/Sessions/SessionDetailView.swift"
            ),
            Self.message(
                role: .assistant,
                text: "Use NaturalLanguage tokenization, embedding cache, and TranscriptAnalysisService for the provider workflow."
            ),
        ]

        let analysis = await TranscriptTermExtractor().extract(session: session, messages: messages)

        #expect(analysis.terms.contains { $0.canonical == "SwiftUI" && $0.kind == .api })
        #expect(analysis.terms.contains { $0.displayName.contains("SessionDetailView.swift") && $0.kind == .filePath })
        #expect(analysis.terms.contains { $0.displayName.contains("bash scripts/run-debug.sh") && $0.kind == .command })
        #expect(analysis.terms.contains { $0.canonical == "build failed" && $0.kind == .error })
        #expect(analysis.terms.contains { $0.canonical == "NaturalLanguage" && $0.kind == .api })
    }

    @Test("Skips natural-language extraction for code-heavy transcript text")
    func skipsNaturalLanguageForCodeHeavyText() async throws {
        let session = Self.session(id: "claude::tool-heavy", provider: .claude)
        let jsonLine = #"{"type":"tool_result","payload":{"path":"ClaudeStats/Services/SessionStore.swift","status":"ok","id":"abc-123"}}"#
        let messages = [
            Self.message(role: .tool, text: String(repeating: jsonLine + "\n", count: 80)),
        ]

        let analysis = await TranscriptTermExtractor().extract(session: session, messages: messages)
        let naturalLanguageCount = analysis.terms.filter { $0.sourceCounts.naturalLanguage > 0 }.count

        #expect(analysis.terms.contains { $0.kind == .filePath && $0.displayName.contains("SessionStore.swift") })
        #expect(naturalLanguageCount < 4)
    }

    private static func session(id: String, provider: ProviderKind) -> Session {
        Session(
            id: id,
            externalID: "analysis",
            provider: provider,
            projectDirectoryName: "-Users-dev-claude-stats",
            filePath: "/tmp/analysis.jsonl",
            cwd: "/Users/dev/claude-stats",
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 1_024,
            stats: SessionStats(
                title: "Analysis Session",
                messageCount: 2,
                firstActivity: nil,
                lastActivity: nil,
                models: [],
                timeline: []
            )
        )
    }

    private static func message(role: SessionTranscriptMessage.Role, text: String) -> SessionTranscriptMessage {
        SessionTranscriptMessage(
            id: UUID().uuidString,
            role: role,
            text: text,
            timestamp: Date(timeIntervalSince1970: 1_000),
            model: nil
        )
    }
}

@Suite("Transcript TF-IDF analyzer")
struct TranscriptTFIDFAnalyzerTests {
    @Test("Common terms are downweighted while project terms rise")
    func ranksProjectTermsAboveCommonTerms() throws {
        let sessions = [
            Self.session(id: "s1"),
            Self.session(id: "s2"),
        ]
        let analyses = [
            Self.analysis(sessionID: "s1", terms: [
                Self.term("common", kind: .general, frequency: 1, weight: 1.0),
                Self.term("SessionStore", kind: .typeName, frequency: 2, weight: 1.7),
            ]),
            Self.analysis(sessionID: "s2", terms: [
                Self.term("common", kind: .general, frequency: 1, weight: 1.0),
            ]),
        ]
        let snapshot = TranscriptTFIDFAnalyzer().snapshot(
            provider: .claude,
            sessions: sessions,
            sessionAnalyses: analyses,
            engine: Self.engine,
            now: Date(timeIntervalSince1970: 1_000)
        )

        let common = try #require(snapshot.terms.first { $0.canonical == "common" })
        let project = try #require(snapshot.terms.first { $0.canonical == "SessionStore" })

        #expect(common.documentFrequency == 2)
        #expect(project.documentFrequency == 1)
        #expect(project.tfidf > common.tfidf)
        #expect(snapshot.terms.first?.canonical == "SessionStore")
    }

    private static let engine = TranscriptAnalysisEngineInfo(
        tokenizerID: "test-tokenizer",
        analysisVersion: "test-analysis",
        displayName: "Test",
        embeddingStatus: .notConfigured
    )

    private static func session(id: String) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: .claude,
            projectDirectoryName: "project",
            filePath: "/tmp/\(id).jsonl",
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 128,
            stats: nil
        )
    }

    static func analysis(sessionID: String, terms: [TranscriptSessionTerm]) -> TranscriptSessionAnalysis {
        TranscriptSessionAnalysis(
            sessionID: sessionID,
            sessionTitle: sessionID,
            projectName: "project",
            terms: terms
        )
    }

    static func term(
        _ canonical: String,
        kind: TranscriptTermKind,
        frequency: Int,
        weight: Double
    ) -> TranscriptSessionTerm {
        var roleCounts = TranscriptRoleCounts()
        roleCounts.add(.user, count: frequency)
        var sourceCounts = TranscriptSourceCounts()
        sourceCounts.add(.naturalLanguage, count: frequency)
        return TranscriptSessionTerm(
            canonical: canonical,
            displayName: canonical,
            kind: kind,
            frequency: frequency,
            weight: weight,
            roleCounts: roleCounts,
            sourceCounts: sourceCounts,
            example: nil
        )
    }
}

@Suite("Transcript analysis index")
struct TranscriptAnalysisIndexTests {
    @Test("Stores analyzed and empty sessions and invalidates metadata changes")
    func indexReadWriteAndInvalidation() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))

        let session = Self.session(id: "claude::cache", provider: .claude, fileSize: 256)
        let key = await index.key(for: session, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        let analysis = Self.analysis(sessionID: session.id, terms: [
            Self.term("SwiftUI", kind: .framework, frequency: 2, weight: 1.7),
        ])

        let cold = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(cold.first?.state == .missNew)

        try await index.writeAnalyzed(analysis, for: key)
        let warm = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(warm.first?.state == .hit)

        let analysisVersionChanged = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-b"
        )
        #expect(analysisVersionChanged.first?.state == .missChanged)

        let emptySession = Self.session(id: "claude::empty", provider: .claude, fileSize: 1)
        let emptyKey = await index.key(for: emptySession, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        try await index.writeEmpty(for: emptySession, key: emptyKey)
        let emptyLookup = try await index.lookup(
            provider: .claude,
            sessions: [emptySession],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(emptyLookup.first?.state == .empty)

        let changedEmpty = Self.session(id: "claude::empty", provider: .claude, fileSize: 2)
        let changedLookup = try await index.lookup(
            provider: .claude,
            sessions: [changedEmpty],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(changedLookup.first?.state == .missChanged)

        let codexScope = try await index.lookup(
            provider: .codex,
            sessions: [Self.session(id: "claude::cache", provider: .codex, fileSize: 256)],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(codexScope.first?.state == .missNew)

        let deleted = try await index.pruneDeleted(provider: .claude, liveSessionIDs: [])
        #expect(deleted == 2)
    }

    @Test("Migrates v1 cache schema without dropping existing session rows")
    func v1MigrationKeepsSessionRows() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("index.sqlite3")
        let session = Self.session(id: "claude::v1", provider: .claude, fileSize: 128)
        let key = await TranscriptAnalysisIndex(url: url).key(
            for: session,
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )

        try Self.createV1Database(at: url, key: key, session: session)

        let index = TranscriptAnalysisIndex(url: url)
        let migrated = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            analysisVersion: "analysis-a"
        )
        #expect(migrated.first?.state == .hit)

        let snapshot = try await index.materializedSnapshot(
            provider: .claude,
            sessions: [session],
            keysBySessionID: [session.id: key],
            engine: Self.engine,
            analysisSignature: "analysis-a",
            runSummary: .empty
        )
        #expect(snapshot.analyzedSessionCount == 1)
        #expect(snapshot.terms.isEmpty)
    }

    @Test("Materialized corpus matches TF-IDF and updates by delta")
    func materializedCorpusDeltaFlow() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))

        let first = Self.session(id: "claude::one", provider: .claude, fileSize: 256)
        let second = Self.session(id: "claude::two", provider: .claude, fileSize: 512)
        let firstAnalysis = Self.analysis(sessionID: first.id, terms: [
            Self.term("common", kind: .general, frequency: 1, weight: 1.0, excerpt: "first common"),
            Self.term("ProjectTerm", kind: .typeName, frequency: 2, weight: 1.7, excerpt: "first project"),
            Self.term("Shared API", displayName: "Shared API", kind: .api, frequency: 1, weight: 1.3, excerpt: "first shared"),
        ])
        let secondAnalysis = Self.analysis(sessionID: second.id, terms: [
            Self.term("common", kind: .general, frequency: 1, weight: 1.0, excerpt: "second common"),
            Self.term("Shared API", displayName: "shared api", kind: .api, frequency: 1, weight: 1.2, excerpt: "second shared"),
        ])
        let firstKey = await index.key(for: first, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        let secondKey = await index.key(for: second, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        try await index.writeAnalyzed(firstAnalysis, for: firstKey)
        try await index.writeAnalyzed(secondAnalysis, for: secondKey)

        try await Self.expectMaterialized(
            index,
            sessions: [first, second],
            keys: [first.id: firstKey, second.id: secondKey],
            analyses: [firstAnalysis, secondAnalysis]
        )

        try await Self.expectMaterialized(
            index,
            sessions: [first, second],
            keys: [first.id: firstKey, second.id: secondKey],
            analyses: [firstAnalysis, secondAnalysis]
        )

        let third = Self.session(id: "claude::three", provider: .claude, fileSize: 768)
        let thirdAnalysis = Self.analysis(sessionID: third.id, terms: [
            Self.term("NewTerm", kind: .framework, frequency: 3, weight: 1.6, excerpt: "third new"),
            Self.term("common", kind: .general, frequency: 1, weight: 1.0, excerpt: "third common"),
        ])
        let thirdKey = await index.key(for: third, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        try await index.writeAnalyzed(thirdAnalysis, for: thirdKey)
        try await Self.expectMaterialized(
            index,
            sessions: [first, second, third],
            keys: [first.id: firstKey, second.id: secondKey, third.id: thirdKey],
            analyses: [firstAnalysis, secondAnalysis, thirdAnalysis]
        )

        let changedFirst = Self.session(id: first.id, provider: .claude, fileSize: 1_024)
        let changedFirstAnalysis = Self.analysis(sessionID: changedFirst.id, terms: [
            Self.term("ChangedTerm", kind: .framework, frequency: 2, weight: 1.8, excerpt: "changed first"),
            Self.term("common", kind: .general, frequency: 1, weight: 1.0, excerpt: "changed common"),
        ])
        let changedFirstKey = await index.key(for: changedFirst, tokenizerID: "tokenizer-a", analysisVersion: "analysis-a")
        try await index.writeAnalyzed(changedFirstAnalysis, for: changedFirstKey)
        try await Self.expectMaterialized(
            index,
            sessions: [changedFirst, second, third],
            keys: [changedFirst.id: changedFirstKey, second.id: secondKey, third.id: thirdKey],
            analyses: [changedFirstAnalysis, secondAnalysis, thirdAnalysis],
            absentTerms: ["ProjectTerm"]
        )

        let deleted = try await index.pruneDeleted(provider: .claude, liveSessionIDs: [second.id, third.id])
        #expect(deleted == 1)
        let afterDelete = try await Self.expectMaterialized(
            index,
            sessions: [second, third],
            keys: [second.id: secondKey, third.id: thirdKey],
            analyses: [secondAnalysis, thirdAnalysis],
            absentTerms: ["ChangedTerm", "ProjectTerm"]
        )
        let shared = try #require(afterDelete.terms.first { $0.canonical == "Shared API" })
        #expect(shared.displayName == "shared api")
        #expect(shared.aliases.isEmpty)
        #expect(shared.examples.first?.excerpt == "second shared")
    }

    static func session(id: String, provider: ProviderKind, fileSize: Int64) -> Session {
        TranscriptAnalysisServiceTests.session(id: id, provider: provider, fileSize: fileSize)
    }

    private static let engine = TranscriptAnalysisEngineInfo(
        tokenizerID: "tokenizer-a",
        analysisVersion: "analysis-a",
        displayName: "Test",
        embeddingStatus: .notConfigured
    )

    private static func analysis(sessionID: String, terms: [TranscriptSessionTerm]) -> TranscriptSessionAnalysis {
        TranscriptTFIDFAnalyzerTests.analysis(sessionID: sessionID, terms: terms)
    }

    private static func term(
        _ canonical: String,
        kind: TranscriptTermKind,
        frequency: Int,
        weight: Double
    ) -> TranscriptSessionTerm {
        term(canonical, displayName: canonical, kind: kind, frequency: frequency, weight: weight)
    }

    private static func term(
        _ canonical: String,
        displayName: String? = nil,
        kind: TranscriptTermKind,
        frequency: Int,
        weight: Double,
        excerpt: String = ""
    ) -> TranscriptSessionTerm {
        var roleCounts = TranscriptRoleCounts()
        roleCounts.add(.user, count: frequency)
        var sourceCounts = TranscriptSourceCounts()
        sourceCounts.add(.naturalLanguage, count: frequency)
        return TranscriptSessionTerm(
            canonical: canonical,
            displayName: displayName ?? canonical,
            kind: kind,
            frequency: frequency,
            weight: weight,
            roleCounts: roleCounts,
            sourceCounts: sourceCounts,
            example: excerpt.isEmpty ? nil : TranscriptTermExample(
                id: "\(canonical)-\(displayName ?? canonical)-example",
                sessionID: "",
                sessionTitle: "",
                projectName: "",
                role: .user,
                excerpt: excerpt,
                timestamp: Date(timeIntervalSince1970: 1_000)
            )
        )
    }

    @discardableResult
    private static func expectMaterialized(
        _ index: TranscriptAnalysisIndex,
        sessions: [Session],
        keys: [String: TranscriptAnalysisKey],
        analyses: [TranscriptSessionAnalysis],
        absentTerms: Set<String> = []
    ) async throws -> TranscriptAnalysisSnapshot {
        let materialized = try await index.materializedSnapshot(
            provider: .claude,
            sessions: sessions,
            keysBySessionID: keys,
            engine: engine,
            analysisSignature: "analysis-a",
            runSummary: .empty,
            now: Date(timeIntervalSince1970: 2_000)
        )
        let expected = TranscriptTFIDFAnalyzer().snapshot(
            provider: .claude,
            sessions: sessions,
            sessionAnalyses: analyses,
            engine: engine,
            analysisSignature: "analysis-a",
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(materialized.analyzedSessionCount == expected.analyzedSessionCount)
        #expect(materialized.sessionAnalyses.map(\.sessionID) == expected.sessionAnalyses.map(\.sessionID))
        #expect(materialized.terms.map(\.canonical) == expected.terms.map(\.canonical))
        for expectedTerm in expected.terms {
            let actual = try #require(materialized.terms.first { $0.canonical == expectedTerm.canonical && $0.kind == expectedTerm.kind })
            #expect(actual.displayName == expectedTerm.displayName)
            #expect(actual.aliases == expectedTerm.aliases)
            #expect(actual.frequency == expectedTerm.frequency)
            #expect(actual.documentFrequency == expectedTerm.documentFrequency)
            #expect(abs(actual.tfidf - expectedTerm.tfidf) < 0.000_001)
            #expect(actual.roleCounts == expectedTerm.roleCounts)
            #expect(actual.sourceCounts == expectedTerm.sourceCounts)
            #expect(actual.examples.map(\.excerpt) == expectedTerm.examples.map(\.excerpt))
        }
        for absent in absentTerms {
            #expect(!materialized.terms.contains { $0.canonical == absent })
        }
        return materialized
    }

    private static func createV1Database(
        at url: URL,
        key: TranscriptAnalysisKey,
        session: Session
    ) throws {
        let connection = try SQLiteConnection(url: url)
        try TranscriptAnalysisIndexSchema.configure(connection)
        try connection.execute(
            """
            CREATE TABLE session_analysis (
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
            CREATE TABLE session_terms (
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
            CREATE TABLE term_examples (
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
        let insert = try connection.prepare(
            """
            INSERT INTO session_analysis (
                key_digest, cache_schema_version, extractor_version, tokenizer_id, dictionary_version,
                options_digest, provider, session_id, file_path_hash, file_size, last_modified_ns,
                status, session_title, project_name, term_count, saved_at, last_accessed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try insert.bind(key.digest, at: 1)
        try insert.bind(key.schemaVersion, at: 2)
        try insert.bind(key.extractorVersion, at: 3)
        try insert.bind(key.tokenizerID, at: 4)
        try insert.bind(key.analysisVersion, at: 5)
        try insert.bind(key.optionsDigest, at: 6)
        try insert.bind(key.provider.rawValue, at: 7)
        try insert.bind(key.sessionID, at: 8)
        try insert.bind(key.filePathHash, at: 9)
        try insert.bind(key.fileSize, at: 10)
        try insert.bind(key.lastModifiedNanoseconds, at: 11)
        try insert.bind("analyzed", at: 12)
        try insert.bind(session.stats?.title ?? session.externalID, at: 13)
        try insert.bind(session.projectDisplayName, at: 14)
        try insert.bind(0, at: 15)
        try insert.bind(1_000.0, at: 16)
        try insert.bind(1_000.0, at: 17)
        try insert.finish()
        try connection.execute("PRAGMA user_version = 1")
    }
}

@Suite("Transcript analysis service")
struct TranscriptAnalysisServiceTests {
    @Test("Uses SQLite incrementally for cache hits new changed deleted and empty sessions")
    func incrementalServiceFlow() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))
        let service = TranscriptAnalysisService(index: index, maxConcurrentSessions: 2)
        let first = Self.session(id: "codex::one", provider: .codex, fileSize: 512)
        let empty = Self.session(id: "codex::empty", provider: .codex, fileSize: 1)
        let loader = MessageLoaderSpy(messages: [
            first.id: [
                Self.message(role: .user, text: "Use SwiftUI and CppJieba for semantic analysis."),
                Self.message(role: .assistant, text: "Run `git status` and inspect project.yml."),
            ],
            empty.id: [],
        ])

        let firstSnapshot = try await service.analyze(
            provider: .codex,
            sessions: [first, empty],
            messageLoader: loader.loader()
        )

        #expect(firstSnapshot.provider == .codex)
        #expect(firstSnapshot.sessionCount == 2)
        #expect(firstSnapshot.analyzedSessionCount == 1)
        #expect(firstSnapshot.runSummary.newCount == 1)
        #expect(firstSnapshot.runSummary.empty == 1)
        #expect(firstSnapshot.terms.contains { $0.canonical == "SwiftUI" })
        #expect(firstSnapshot.terms.contains { $0.kind == .command && $0.displayName.contains("git status") })
        #expect(firstSnapshot.engine.embeddingStatus == .notConfigured)
        #expect(await loader.callCount(for: first.id) == 1)
        #expect(await loader.callCount(for: empty.id) == 1)

        let warmSnapshot = try await service.analyze(
            provider: .codex,
            sessions: [first, empty],
            messageLoader: loader.loader()
        )
        #expect(warmSnapshot.runSummary.reused == 1)
        #expect(warmSnapshot.runSummary.empty == 1)
        #expect(await loader.callCount(for: first.id) == 1)
        #expect(await loader.callCount(for: empty.id) == 1)

        let second = Self.session(id: "codex::two", provider: .codex, fileSize: 640)
        await loader.setMessages([
            Self.message(role: .user, text: "Add SQLiteConnection and TranscriptAnalysisIndex."),
        ], for: second.id)
        let withNew = try await service.analyze(
            provider: .codex,
            sessions: [first, empty, second],
            messageLoader: loader.loader()
        )
        #expect(withNew.runSummary.reused == 1)
        #expect(withNew.runSummary.newCount == 1)
        #expect(withNew.runSummary.empty == 1)
        #expect(await loader.callCount(for: first.id) == 1)
        #expect(await loader.callCount(for: second.id) == 1)

        let changedFirst = Self.session(id: first.id, provider: .codex, fileSize: 768)
        await loader.setMessages([
            Self.message(role: .user, text: "Changed transcript now focuses on NaturalLanguage and SQLite."),
        ], for: first.id)
        let changedSnapshot = try await service.analyze(
            provider: .codex,
            sessions: [changedFirst, second],
            messageLoader: loader.loader()
        )
        #expect(changedSnapshot.runSummary.reused == 1)
        #expect(changedSnapshot.runSummary.changed == 1)
        #expect(changedSnapshot.runSummary.deleted == 1)
        #expect(changedSnapshot.analyzedSessionCount == 2)
        #expect(changedSnapshot.sessionAnalysis(for: empty.id) == nil)
        #expect(await loader.callCount(for: first.id) == 2)
        #expect(await loader.callCount(for: second.id) == 1)
    }


    static func session(id: String, provider: ProviderKind, fileSize: Int64) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: provider,
            projectDirectoryName: "project",
            filePath: "/tmp/\(id).jsonl",
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_000 + Double(fileSize)),
            fileSize: fileSize,
            stats: SessionStats(
                title: "Provider Session",
                messageCount: 2,
                firstActivity: nil,
                lastActivity: nil,
                models: [],
                timeline: []
            )
        )
    }

    static func message(role: SessionTranscriptMessage.Role, text: String) -> SessionTranscriptMessage {
        SessionTranscriptMessage(
            id: UUID().uuidString,
            role: role,
            text: text,
            timestamp: Date(timeIntervalSince1970: 1_000),
            model: nil
        )
    }
}


@Suite("Transcript analysis store")
struct TranscriptAnalysisStoreTests {
    @Test("Provider scoped loading and progress are observable")
    @MainActor
    func providerScopedProgressIsObservable() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))
        let service = TranscriptAnalysisService(index: index, maxConcurrentSessions: 1)
        let store = TranscriptAnalysisStore(service: service)
        let sessions = (1 ... 3).map {
            TranscriptAnalysisServiceTests.session(id: "codex::\($0)", provider: .codex, fileSize: Int64(512 + $0))
        }
        let loader = MessageLoaderSpy(
            messages: Dictionary(uniqueKeysWithValues: sessions.map { session in
                (
                    session.id,
                    [TranscriptAnalysisServiceTests.message(
                        role: .user,
                        text: "Analyze SwiftUI progress updates for TranscriptAnalysisStore \(session.id)."
                    )]
                )
            }),
            delay: .milliseconds(40)
        )
        let observation = ObservationChangeFlag()

        withObservationTracking {
            _ = store.isLoading(for: .codex)
            _ = store.progress(for: .codex)
        } onChange: {
            Task { await observation.markChanged() }
        }

        store.reload(
            provider: .codex,
            sessions: sessions,
            messageLoader: loader.loader()
        )

        #expect(store.isLoading(for: .codex))
        #expect(!store.isLoading(for: .claude))
        #expect(store.progress(for: .codex).phase == .loadingIndex)

        try await waitFor { await observation.didChange() }
        try await waitFor {
            let progress = store.progress(for: .codex)
            return progress.total == sessions.count && progress.completed > 0
        }

        let inFlightProgress = store.progress(for: .codex)
        #expect(inFlightProgress.currentSessionTitle != nil)
        #expect(store.snapshot(for: .claude) == nil)

        try await waitFor {
            store.snapshot(for: .codex) != nil && !store.isLoading(for: .codex)
        }

        let snapshot = try #require(store.snapshot(for: .codex))
        #expect(snapshot.analyzedSessionCount == sessions.count)
        #expect(store.progress(for: .codex) == .idle)
        #expect(await loader.callCount(for: sessions[0].id) == 1)
    }

    @Test("Duplicate loadIfNeeded reuses in-flight run")
    @MainActor
    func duplicateLoadIfNeededReusesInFlightRun() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))
        let service = TranscriptAnalysisService(index: index, maxConcurrentSessions: 1)
        let store = TranscriptAnalysisStore(service: service)
        let session = TranscriptAnalysisServiceTests.session(id: "codex::in-flight", provider: .codex, fileSize: 1_024)
        let loader = BlockingMessageLoaderSpy(messages: [
            session.id: [TranscriptAnalysisServiceTests.message(role: .user, text: "Analyze design token and service mesh progress.")],
        ])

        store.loadIfNeeded(provider: .codex, sessions: [session], messageLoader: loader.loader())

        try await waitFor {
            await loader.callCount(for: session.id) == 1
        }
        #expect(store.isLoading(for: .codex))

        store.loadIfNeeded(provider: .codex, sessions: [session], messageLoader: loader.loader())
        try await Task.sleep(for: .milliseconds(100))

        #expect(await loader.callCount(for: session.id) == 1)

        await loader.resumeAll()
        try await waitFor {
            store.snapshot(for: .codex) != nil && !store.isLoading(for: .codex)
        }

        #expect(store.progress(for: .codex) == .idle)
    }

    @Test("Superseded provider run does not leave loading stuck")
    @MainActor
    func supersededRunDoesNotLeaveLoadingStuck() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))
        let service = TranscriptAnalysisService(index: index, maxConcurrentSessions: 1)
        let store = TranscriptAnalysisStore(service: service)
        let session = TranscriptAnalysisServiceTests.session(id: "codex::cancel", provider: .codex, fileSize: 900)
        let slowLoader = MessageLoaderSpy(
            messages: [
                session.id: [TranscriptAnalysisServiceTests.message(role: .user, text: "Slow SwiftUI analysis run.")],
            ],
            delay: .milliseconds(200)
        )
        let fastLoader = MessageLoaderSpy(messages: [
            session.id: [TranscriptAnalysisServiceTests.message(role: .user, text: "Fast NaturalLanguage analysis run.")],
        ])

        store.reload(provider: .codex, sessions: [session], messageLoader: slowLoader.loader())
        #expect(store.isLoading(for: .codex))

        store.reload(provider: .codex, sessions: [session], messageLoader: fastLoader.loader())

        try await waitFor {
            store.snapshot(for: .codex) != nil && !store.isLoading(for: .codex)
        }

        #expect(store.progress(for: .codex) == .idle)
        #expect(await fastLoader.callCount(for: session.id) == 1)
    }
}

private actor BlockingMessageLoaderSpy {
    private var messages: [String: [SessionTranscriptMessage]]
    private var calls: [String: Int] = [:]
    private var continuations: [String: [CheckedContinuation<[SessionTranscriptMessage], Never>]] = [:]

    init(messages: [String: [SessionTranscriptMessage]]) {
        self.messages = messages
    }

    nonisolated func loader() -> TranscriptMessageLoader {
        { session in
            await self.load(session)
        }
    }

    func callCount(for sessionID: String) -> Int {
        calls[sessionID, default: 0]
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for (sessionID, continuations) in pending {
            let result = messages[sessionID] ?? []
            for continuation in continuations {
                continuation.resume(returning: result)
            }
        }
    }

    private func load(_ session: Session) async -> [SessionTranscriptMessage] {
        calls[session.id, default: 0] += 1
        return await withCheckedContinuation { continuation in
            continuations[session.id, default: []].append(continuation)
        }
    }
}

private actor MessageLoaderSpy {
    private var messages: [String: [SessionTranscriptMessage]]
    private var calls: [String: Int] = [:]
    private let delay: Duration?

    init(messages: [String: [SessionTranscriptMessage]], delay: Duration? = nil) {
        self.messages = messages
        self.delay = delay
    }

    nonisolated func loader() -> TranscriptMessageLoader {
        { session in
            await self.load(session)
        }
    }

    func setMessages(_ newMessages: [SessionTranscriptMessage], for sessionID: String) {
        messages[sessionID] = newMessages
    }

    func callCount(for sessionID: String) -> Int {
        calls[sessionID, default: 0]
    }

    private func load(_ session: Session) async -> [SessionTranscriptMessage] {
        if let delay {
            try? await Task.sleep(for: delay)
        }
        calls[session.id, default: 0] += 1
        return messages[session.id] ?? []
    }
}

private actor ObservationChangeFlag {
    private var changed = false

    func markChanged() {
        changed = true
    }

    func didChange() -> Bool {
        changed
    }
}

private func waitFor(_ predicate: @escaping @MainActor () async -> Bool) async throws {
    for _ in 0 ..< 200 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await predicate())
}
