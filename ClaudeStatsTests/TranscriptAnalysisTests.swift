import Foundation
import Observation
import Testing
@testable import ClaudeStats

@Suite("Jieba tokenizer")
struct JiebaTokenizerTests {
    @Test("Chinese tokenizer uses bundled CppJieba dictionaries and custom words")
    func bundledJiebaAndCustomDictionary() async {
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

@Suite("Technical term dictionary")
struct TechnicalTermDictionaryTests {
    @Test("Aliases normalize to canonical technical terms")
    func aliasesNormalize() {
        let dictionary = TechnicalTermDictionary()

        #expect(dictionary.canonicalize("Swift UI")?.canonical == "SwiftUI")
        #expect(dictionary.canonicalize("github actions")?.canonical == "GitHub Actions")
        #expect(dictionary.isStopword("the"))
        #expect(dictionary.matches(in: "Use Natural Language with SwiftUI").map(\.canonical).contains("NaturalLanguage"))
    }

    @Test("Normalizer handles UI vocabulary aliases and one-character typo phrases")
    func normalizerHandlesTechnicalVocabulary() {
        let dictionary = TechnicalTermDictionary()

        #expect(TermNormalizer.normalizedKey("MenuBarExtra") == TermNormalizer.normalizedKey("menu bar extra"))
        #expect(dictionary.canonicalize("mainWindow")?.canonical == "main window")
        #expect(dictionary.canonicalize("main windows")?.canonical == "main window")
        #expect(dictionary.canonicalize("mian windows")?.canonical == "main window")
        #expect(dictionary.canonicalize("主窗口")?.canonical == "main window")
        #expect(dictionary.canonicalize("zIndex")?.canonical == "z-index")
        #expect(dictionary.canonicalize("z_index")?.canonical == "z-index")
        #expect(dictionary.canonicalize("层级")?.canonical == "z-index")
    }

    @Test("Dictionary matching counts occurrences without overmatching generic words")
    func dictionaryMatchingCountsOccurrences() {
        let dictionary = TechnicalTermDictionary()
        let matches = dictionary.matches(in: "MenuBarExtra and menu bar extra changed zIndex, z-index, and plain menu text.")
        let menuCount = matches.filter { $0.canonical == "MenuBarExtra" }.count
        let zIndexCount = matches.filter { $0.canonical == "z-index" }.count

        #expect(menuCount == 2)
        #expect(zIndexCount == 2)
        #expect(dictionary.canonicalize("main menu") == nil)
    }

    @Test("Repository merges built-in global and project dictionaries with digest invalidation")
    func repositoryMergePrecedenceAndDigest() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }
        let homeRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-stats-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeRoot) }

        let builtInURL = temp.appendingPathComponent("technical_terms.json")
        let globalURL = temp.appendingPathComponent("user_terms.json")
        let projectRoot = homeRoot.appendingPathComponent("parent", isDirectory: true)
        let childRoot = projectRoot.appendingPathComponent("child", isDirectory: true)
        let parentTerms = projectRoot.appendingPathComponent(".claude-stats/terms.json")
        let childTerms = childRoot.appendingPathComponent(".claude-stats/terms.json")

        try Self.writeDocument(
            TechnicalTermDocument(
                terms: [
                    TechnicalTermEntry(canonical: "MenuBarExtra", kind: .api, aliases: ["menu bar extra"], weight: 1.0),
                    TechnicalTermEntry(canonical: "OverrideMe", kind: .api, aliases: ["built"], weight: 1.0, tags: ["built"]),
                ],
                stopwords: ["noise"]
            ),
            to: builtInURL
        )
        try Self.writeDocument(
            TechnicalTermDocument(terms: [
                TechnicalTermEntry(canonical: "MenuBarExtra", kind: .api, enabled: false),
                TechnicalTermEntry(canonical: "OverrideMe", kind: .framework, aliases: ["global"], weight: 2.0, tags: ["global"]),
            ]),
            to: globalURL
        )
        try Self.writeDocument(
            TechnicalTermDocument(terms: [
                TechnicalTermEntry(canonical: "ParentTerm", kind: .general, aliases: ["parent term"], weight: 1.4),
                TechnicalTermEntry(canonical: "OverrideMe", kind: .workflow, aliases: ["parent"], weight: 3.0, tags: ["parent"]),
            ]),
            to: parentTerms
        )
        try Self.writeDocument(
            TechnicalTermDocument(terms: [
                TechnicalTermEntry(canonical: "OverrideMe", kind: .typeName, aliases: ["child"], weight: 4.0, tags: ["child"]),
            ]),
            to: childTerms
        )

        let repository = TechnicalTermDictionaryRepository(builtInURL: builtInURL, globalURL: globalURL)
        let session = Self.session(id: "codex::dictionary", cwd: childRoot.path)
        let snapshot = await repository.snapshot(for: session)
        let dictionary = snapshot.dictionary

        #expect(dictionary.canonicalize("MenuBarExtra") == nil)
        #expect(dictionary.canonicalize("parent term")?.canonical == "ParentTerm")
        let override = try #require(dictionary.canonicalize("built"))
        #expect(override.kind == TranscriptTermKind.typeName)
        #expect(override.weight == 4.0)
        #expect(Set(override.aliases).isSuperset(of: ["built", "global", "parent", "child"]))
        #expect(Set(override.tags).isSuperset(of: ["built", "global", "parent", "child"]))

        let oldDigest = snapshot.digest
        try await repository.saveEntry(
            TechnicalTermEntry(canonical: "NewProjectTerm", kind: .api),
            originalCanonical: nil,
            scope: .project,
            projectPath: childRoot.path
        )
        let changed = await repository.snapshot(for: session)
        #expect(changed.digest != oldDigest)
        #expect(changed.dictionary.canonicalize("NewProjectTerm")?.canonical == "NewProjectTerm")
    }

    @Test("Import accepts CSV and TXT rows and export round-trips JSON")
    func importAndExportDictionaries() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let repository = TechnicalTermDictionaryRepository(
            builtInURL: temp.appendingPathComponent("missing.json"),
            globalURL: temp.appendingPathComponent("user_terms.json")
        )
        let csv = temp.appendingPathComponent("terms.csv")
        let txt = temp.appendingPathComponent("terms.txt")
        let export = temp.appendingPathComponent("export.json")
        try TempDir.write(
            """
            canonical,kind,aliases,weight,enabled,tags
            Custom API,api,custom api|自定义 API,2.1,true,ui|api
            ,api,missing,1.0,true,bad
            Custom API,framework,custom framework,2.5,true,merged
            """,
            to: csv
        )
        try TempDir.write(
            """
            # comments are skipped
            Text Term
            z-order
            """,
            to: txt
        )

        let csvReport = try await repository.importTerms(from: csv, scope: .global, projectPath: nil)
        let txtReport = try await repository.importTerms(from: txt, scope: .global, projectPath: nil)
        try await repository.exportTerms(to: export, scope: .global, projectPath: nil)
        let exported = try JSONDecoder().decode(TechnicalTermDocument.self, from: Data(contentsOf: export))
        let custom = try #require(exported.terms.first { $0.canonical == "Custom API" })

        #expect(csvReport.imported == 2)
        #expect(csvReport.skipped == 1)
        #expect(txtReport.imported == 2)
        #expect(custom.kind == .framework)
        #expect(custom.weight == 2.5)
        #expect(Set(custom.aliases).isSuperset(of: ["custom api", "自定义 API", "custom framework"]))
        #expect(exported.terms.contains { $0.canonical == "Text Term" })
    }

    private static func session(id: String, cwd: String) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: .codex,
            projectDirectoryName: "project",
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 128,
            stats: nil
        )
    }

    private static func writeDocument(_ document: TechnicalTermDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
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

        #expect(analysis.terms.contains { $0.canonical == "SwiftUI" && $0.kind == .framework })
        #expect(analysis.terms.contains { $0.displayName.contains("SessionDetailView.swift") && $0.kind == .filePath })
        #expect(analysis.terms.contains { $0.displayName.contains("bash scripts/run-debug.sh") && $0.kind == .command })
        #expect(analysis.terms.contains { $0.canonical == "build failed" && $0.kind == .error })
        #expect(analysis.terms.contains { $0.canonical == "NaturalLanguage" && $0.kind == .framework })
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
        dictionaryVersion: "test-dictionary",
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
        let key = await index.key(for: session, tokenizerID: "tokenizer-a", dictionaryVersion: "dictionary-a")
        let analysis = Self.analysis(sessionID: session.id, terms: [
            Self.term("SwiftUI", kind: .framework, frequency: 2, weight: 1.7),
        ])

        let cold = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-a"
        )
        #expect(cold.first?.state == .missNew)

        try await index.writeAnalyzed(analysis, for: key)
        let warm = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-a"
        )
        if case .hit(let cached) = try #require(warm.first?.state) {
            #expect(cached == analysis)
        } else {
            Issue.record("Expected analyzed cache hit")
        }

        let dictionaryChanged = try await index.lookup(
            provider: .claude,
            sessions: [session],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-b"
        )
        #expect(dictionaryChanged.first?.state == .missChanged)

        let emptySession = Self.session(id: "claude::empty", provider: .claude, fileSize: 1)
        let emptyKey = await index.key(for: emptySession, tokenizerID: "tokenizer-a", dictionaryVersion: "dictionary-a")
        try await index.writeEmpty(for: emptySession, key: emptyKey)
        let emptyLookup = try await index.lookup(
            provider: .claude,
            sessions: [emptySession],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-a"
        )
        #expect(emptyLookup.first?.state == .empty)

        let changedEmpty = Self.session(id: "claude::empty", provider: .claude, fileSize: 2)
        let changedLookup = try await index.lookup(
            provider: .claude,
            sessions: [changedEmpty],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-a"
        )
        #expect(changedLookup.first?.state == .missChanged)

        let codexScope = try await index.lookup(
            provider: .codex,
            sessions: [Self.session(id: "claude::cache", provider: .codex, fileSize: 256)],
            tokenizerID: "tokenizer-a",
            dictionaryVersion: "dictionary-a"
        )
        #expect(codexScope.first?.state == .missNew)

        let deleted = try await index.pruneDeleted(provider: .claude, liveSessionIDs: [])
        #expect(deleted == 2)
    }

    static func session(id: String, provider: ProviderKind, fileSize: Int64) -> Session {
        TranscriptAnalysisServiceTests.session(id: id, provider: provider, fileSize: fileSize)
    }

    private static func analysis(sessionID: String, terms: [TranscriptSessionTerm]) -> TranscriptSessionAnalysis {
        TranscriptTFIDFAnalyzerTests.analysis(sessionID: sessionID, terms: terms)
    }

    private static func term(
        _ canonical: String,
        kind: TranscriptTermKind,
        frequency: Int,
        weight: Double
    ) -> TranscriptSessionTerm {
        TranscriptTFIDFAnalyzerTests.term(canonical, kind: kind, frequency: frequency, weight: weight)
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

    @Test("Dictionary digest changes invalidate cached session analyses")
    func dictionaryDigestInvalidatesCache() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = DictionarySnapshotSpy(snapshot: .make(
            entries: [TechnicalTermEntry(canonical: "AlphaTerm", kind: .api, aliases: ["alpha term"], weight: 2.0)],
            stopwords: []
        ))
        let index = TranscriptAnalysisIndex(url: root.appendingPathComponent("index.sqlite3"))
        let service = TranscriptAnalysisService(
            index: index,
            maxConcurrentSessions: 1,
            dictionaryResolver: resolver.resolver()
        )
        let session = Self.session(id: "codex::dict-cache", provider: .codex, fileSize: 512)
        let loader = MessageLoaderSpy(messages: [
            session.id: [
                Self.message(role: .user, text: "AlphaTerm and BetaTerm were changed in the session."),
            ],
        ])

        let first = try await service.analyze(provider: .codex, sessions: [session], messageLoader: loader.loader())
        let warm = try await service.analyze(provider: .codex, sessions: [session], messageLoader: loader.loader())
        #expect(first.runSummary.newCount == 1)
        #expect(warm.runSummary.reused == 1)
        #expect(await loader.callCount(for: session.id) == 1)

        await resolver.set(.make(
            entries: [
                TechnicalTermEntry(canonical: "AlphaTerm", kind: .api, aliases: ["alpha term"], weight: 2.0),
                TechnicalTermEntry(canonical: "BetaTerm", kind: .api, aliases: ["beta term"], weight: 2.0),
            ],
            stopwords: []
        ))
        let changed = try await service.analyze(provider: .codex, sessions: [session], messageLoader: loader.loader())
        #expect(changed.runSummary.changed == 1)
        #expect(changed.terms.contains { $0.canonical == "BetaTerm" })
        #expect(await loader.callCount(for: session.id) == 2)
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

private actor DictionarySnapshotSpy {
    private var snapshot: TechnicalTermDictionarySnapshot

    init(snapshot: TechnicalTermDictionarySnapshot) {
        self.snapshot = snapshot
    }

    nonisolated func resolver() -> TranscriptDictionaryResolver {
        { _ in
            await self.current()
        }
    }

    func set(_ snapshot: TechnicalTermDictionarySnapshot) {
        self.snapshot = snapshot
    }

    private func current() -> TechnicalTermDictionarySnapshot {
        snapshot
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
