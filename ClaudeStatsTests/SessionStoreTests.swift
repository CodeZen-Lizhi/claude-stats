import Foundation
import Testing
@testable import ClaudeStats

@Suite("Session store")
struct SessionStoreTests {
    @MainActor
    @Test("Refresh reparses same-size sessions when last modified changes")
    func refreshReparsesSameSizeModifiedSession() async {
        let provider = MutableSessionProvider(
            sessions: [
                Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 42),
            ],
            statsByID: ["project::session": Self.stats(title: "First")]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        #expect(store.sessions.first?.stats?.title == "First")

        provider.update(
            sessions: [
                Self.session(lastModified: Date(timeIntervalSince1970: 2_000), fileSize: 42),
            ],
            statsByID: ["project::session": Self.stats(title: "Second")]
        )

        await store.refresh()

        #expect(provider.parseCalls() == 2)
        #expect(store.sessions.first?.stats?.title == "Second")
    }

    @MainActor
    @Test("Git attribution revision changes only when repo source inputs change")
    func gitAttributionRevisionIgnoresStatsOnlyRefreshes() async {
        let first = Self.session(
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 42,
            cwd: "/tmp/project"
        )
        let provider = MutableSessionProvider(
            sessions: [first],
            statsByID: [first.id: Self.stats(title: "First", tokens: 100)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        let initialRevision = store.gitAttributionRevision

        let statsOnlyChange = Self.session(
            lastModified: Date(timeIntervalSince1970: 2_000),
            fileSize: 42,
            cwd: "/tmp/project"
        )
        provider.update(
            sessions: [statsOnlyChange],
            statsByID: [statsOnlyChange.id: Self.stats(title: "Second", tokens: 120)]
        )

        await store.refresh()

        #expect(store.gitAttributionRevision == initialRevision)

        let cwdChange = Self.session(
            lastModified: Date(timeIntervalSince1970: 3_000),
            fileSize: 42,
            cwd: "/tmp/other-project"
        )
        provider.update(
            sessions: [cwdChange],
            statsByID: [cwdChange.id: Self.stats(title: "Third", tokens: 140)]
        )

        await store.refresh()

        #expect(store.gitAttributionRevision == initialRevision + 1)
    }

    @MainActor
    @Test("Unchanged sessions are restored from ledger without reparsing")
    func unchangedSessionsRestoreFromLedgerWithoutReparsing() async {
        let session = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 42)
        let ledger = Self.temporaryLedger()
        let provider = MutableSessionProvider(
            sessions: [session],
            statsByID: [session.id: Self.stats(title: "Persisted", tokens: 100)]
        )
        let firstStore = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger
        )

        await firstStore.refresh()
        #expect(provider.parseCalls() == 1)

        provider.update(sessions: [session], statsByID: [:])
        let restarted = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger
        )

        await restarted.refresh()

        #expect(provider.parseCalls() == 1)
        #expect(restarted.sessions.first?.stats?.title == "Persisted")
        #expect(restarted.summary(for: .allTime).totalTokens == 100)
    }

    @MainActor
    @Test("Historical event costs are read from ledger instead of recomputed")
    func historicalEventCostsAreReadFromLedger() async {
        let session = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 42)
        let ledger = Self.temporaryLedger()
        let provider = MutableSessionProvider(
            sessions: [session],
            statsByID: [session.id: Self.stats(title: "Original Price", tokens: 100, cost: 1.23)]
        )
        let firstStore = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger
        )

        await firstStore.refresh()
        #expect(abs(firstStore.summary(for: .allTime).totalCost - 1.23) < 1e-9)

        provider.update(
            sessions: [session],
            statsByID: [session.id: Self.stats(title: "Changed Price", tokens: 100, cost: 9.99)]
        )
        let restarted = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger
        )

        await restarted.refresh()

        #expect(provider.parseCalls() == 1)
        #expect(abs(restarted.summary(for: .allTime).totalCost - 1.23) < 1e-9)
    }

    @MainActor
    @Test("Deleted transcripts disappear from sessions while ledger usage remains")
    func deletedTranscriptDoesNotRemoveLedgerTotals() async {
        let session = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 42)
        let provider = MutableSessionProvider(
            sessions: [session],
            statsByID: [session.id: Self.stats(title: "Gone", tokens: 250)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        #expect(store.sessions.count == 1)
        #expect(store.summary(for: .allTime).totalTokens == 250)

        provider.update(sessions: [], statsByID: [:])
        await store.refresh()

        #expect(store.sessions.isEmpty)
        #expect(store.summary(for: .allTime).totalTokens == 250)
    }

    @MainActor
    @Test("Deleting a session trashes transcript, hides it, and preserves ledger and git history")
    func deleteSessionTrashesTranscriptAndPreservesHistory() async {
        let session = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 42)
        let ledger = Self.temporaryLedger()
        let deleted = Self.temporaryDeletedStore()
        var trashedPaths: [String] = []
        let provider = MutableSessionProvider(
            sessions: [session],
            statsByID: [session.id: Self.stats(title: "Deleted", tokens: 250)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger,
            deletedSessions: deleted,
            trashTranscript: { trashedPaths.append($0.path) }
        )

        await store.refresh()
        #expect(store.sessions.map(\.id) == [session.id])
        #expect(store.summary(for: .allTime).totalTokens == 250)

        let result = await store.deleteSession(store.sessions[0])

        #expect(result.deletedIDs == Set([session.id]))
        #expect(result.failures.isEmpty)
        #expect(trashedPaths == [session.filePath])
        #expect(store.sessions.isEmpty)
        #expect(store.summary(for: .allTime).totalTokens == 250)
        #expect(store.gitAttributionSessions.map(\.id).contains(session.id))

        provider.update(sessions: [session], statsByID: [:])
        let restarted = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger,
            deletedSessions: deleted,
            trashTranscript: { _ in }
        )

        await restarted.refresh()

        #expect(restarted.sessions.isEmpty)
        #expect(restarted.summary(for: .allTime).totalTokens == 250)
        #expect(restarted.gitAttributionSessions.map(\.id).contains(session.id))
    }

    @MainActor
    @Test("Batch delete keeps failures visible while successful deletes stay hidden")
    func batchDeleteKeepsFailuresVisible() async {
        let first = Self.session(
            id: "project::first",
            externalID: "first",
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 42
        )
        let second = Self.session(
            id: "project::second",
            externalID: "second",
            lastModified: Date(timeIntervalSince1970: 2_000),
            fileSize: 42
        )
        let provider = MutableSessionProvider(
            sessions: [first, second],
            statsByID: [
                first.id: Self.stats(title: "First", tokens: 100),
                second.id: Self.stats(title: "Second", tokens: 200),
            ]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger(),
            deletedSessions: Self.temporaryDeletedStore(),
            trashTranscript: { url in
                if url.path == second.filePath {
                    throw NSError(domain: "SessionStoreTests", code: 7, userInfo: [
                        NSLocalizedDescriptionKey: "trash denied"
                    ])
                }
            }
        )

        await store.refresh()
        let result = await store.deleteSessions(store.sessions)

        #expect(result.deletedIDs == Set([first.id]))
        #expect(result.failures.map(\.sessionID) == [second.id])
        #expect(store.sessions.map(\.id) == [second.id])
        #expect(store.summary(for: .allTime).totalTokens == 300)
    }

    @MainActor
    @Test("Deleting parent hides folded child while preserving historical attribution")
    func deleteParentHidesChildAndPreservesHistory() async {
        let parent = Self.session(
            id: "codex::parent",
            externalID: "parent",
            lastModified: Date(timeIntervalSince1970: 2_000),
            fileSize: 80,
            cwd: "/tmp/project"
        )
        let child = Self.session(
            id: "codex::child",
            externalID: "child",
            lastModified: Date(timeIntervalSince1970: 2_010),
            fileSize: 70,
            cwd: "/tmp/project/.agents/worker",
            agentInfo: SessionAgentInfo(
                threadSource: "subagent",
                parentSessionID: "codex::parent",
                nickname: "Worker",
                role: "trellis-implement",
                path: "/root/worker"
            )
        )
        let provider = MutableSessionProvider(
            sessions: [parent, child],
            statsByID: [
                parent.id: Self.stats(title: "Parent", tokens: 100, at: Date(timeIntervalSince1970: 2_000)),
                child.id: Self.stats(title: "Child", tokens: 50, at: Date(timeIntervalSince1970: 2_005)),
            ]
        )
        let ledger = Self.temporaryLedger()
        let deleted = Self.temporaryDeletedStore()
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger,
            deletedSessions: deleted,
            trashTranscript: { _ in }
        )

        await store.refresh()
        #expect(store.sessions.map(\.id) == [parent.id])
        #expect(store.sessions.first?.stats?.totalTokens == 150)

        let result = await store.deleteSession(store.sessions[0])

        #expect(result.deletedIDs == Set([child.id, parent.id]))
        #expect(store.sessions.isEmpty)
        #expect(store.summary(for: .allTime).totalTokens == 150)
        #expect(store.gitAttributionSessions.first?.id == parent.id)
        #expect(store.gitAttributionSessions.first?.childSessions.map(\.id) == [child.id])
        #expect(store.gitAttributionSessions.first?.stats?.totalTokens == 150)

        provider.update(sessions: [parent, child], statsByID: [:])
        let restarted = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger,
            deletedSessions: deleted,
            trashTranscript: { _ in }
        )

        await restarted.refresh()

        #expect(restarted.sessions.isEmpty)
        #expect(restarted.gitAttributionSessions.first?.id == parent.id)
        #expect(restarted.gitAttributionSessions.first?.childSessions.map(\.id) == [child.id])
        #expect(restarted.gitAttributionSessions.first?.stats?.totalTokens == 150)
    }

    @MainActor
    @Test("Child agent sessions are folded into parent session")
    func childAgentSessionsFoldIntoParent() async {
        let parent = Self.session(
            id: "codex::parent",
            externalID: "parent",
            lastModified: Date(timeIntervalSince1970: 2_000),
            fileSize: 80,
            cwd: "/tmp/project"
        )
        let child = Self.session(
            id: "codex::child",
            externalID: "child",
            lastModified: Date(timeIntervalSince1970: 2_010),
            fileSize: 70,
            cwd: "/tmp/project",
            agentInfo: SessionAgentInfo(
                threadSource: "subagent",
                parentSessionID: "codex::parent",
                nickname: "Worker",
                role: "trellis-implement",
                path: "/root/worker"
            )
        )
        let provider = MutableSessionProvider(
            sessions: [parent, child],
            statsByID: [
                parent.id: Self.stats(title: "Parent", tokens: 100, at: Date(timeIntervalSince1970: 2_000)),
                child.id: Self.stats(title: "Child", tokens: 50, at: Date(timeIntervalSince1970: 2_005)),
            ],
            messagesByID: [
                parent.id: [Self.message(id: "p", text: "parent")],
                child.id: [Self.message(id: "c", text: "child")],
            ]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()

        #expect(store.sessions.map(\.id) == [parent.id])
        #expect(store.sessions.first?.childSessions.map(\.id) == [child.id])
        #expect(store.sessions.first?.stats?.totalTokens == 150)

        let messages = await store.transcriptMessages(for: store.sessions[0])
        #expect(messages.map(\.text).contains("parent"))
        #expect(messages.map(\.text).contains("child"))
        #expect(messages.contains { $0.text.contains("Subagent: Worker / trellis-implement") })
    }

    @MainActor
    @Test("Nested child agent sessions fold into the root parent")
    func nestedChildAgentSessionsFoldIntoRootParent() async {
        let root = Self.session(
            id: "codex::root",
            externalID: "root",
            lastModified: Date(timeIntervalSince1970: 3_000),
            fileSize: 80
        )
        let child = Self.session(
            id: "codex::child",
            externalID: "child",
            lastModified: Date(timeIntervalSince1970: 3_010),
            fileSize: 70,
            agentInfo: SessionAgentInfo(
                threadSource: "subagent",
                parentSessionID: "codex::root",
                nickname: "Planner",
                role: nil,
                path: nil
            )
        )
        let grandchild = Self.session(
            id: "codex::grandchild",
            externalID: "grandchild",
            lastModified: Date(timeIntervalSince1970: 3_020),
            fileSize: 60,
            agentInfo: SessionAgentInfo(
                threadSource: "subagent",
                parentSessionID: "codex::child",
                nickname: "Worker",
                role: nil,
                path: nil
            )
        )
        let provider = MutableSessionProvider(
            sessions: [root, child, grandchild],
            statsByID: [
                root.id: Self.stats(title: "Root", tokens: 100, at: Date(timeIntervalSince1970: 3_000)),
                child.id: Self.stats(title: "Child", tokens: 50, at: Date(timeIntervalSince1970: 3_010)),
                grandchild.id: Self.stats(title: "Grandchild", tokens: 25, at: Date(timeIntervalSince1970: 3_020)),
            ],
            messagesByID: [
                root.id: [Self.message(id: "root-message", text: "root")],
                child.id: [Self.message(id: "child-message", text: "child")],
                grandchild.id: [Self.message(id: "grandchild-message", text: "grandchild")],
            ]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()

        #expect(store.sessions.map(\.id) == [root.id])
        #expect(store.sessions.first?.childSessions.map(\.id) == [child.id])
        #expect(store.sessions.first?.childSessions.first?.childSessions.map(\.id) == [grandchild.id])
        #expect(store.sessions.first?.stats?.totalTokens == 175)
        #expect(store.summary(for: .allTime).sessionCount == 1)

        let messages = await store.transcriptMessages(for: store.sessions[0])
        #expect(messages.map(\.text).contains("root"))
        #expect(messages.map(\.text).contains("child"))
        #expect(messages.map(\.text).contains("grandchild"))
        #expect(messages.contains { $0.text.contains("Subagent: Planner") && $0.text.contains("Tokens: 50") })
        #expect(messages.contains { $0.text.contains("Subagent: Worker") && $0.text.contains("Tokens: 25") })
    }

    @MainActor
    @Test("Appended session bytes parse incrementally and reuse ledger totals")
    func appendedSessionBytesParseIncrementally() async {
        let initial = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 100)
        let appended = Self.session(lastModified: Date(timeIntervalSince1970: 1_060), fileSize: 160)
        let provider = MutableSessionProvider(
            sessions: [initial],
            statsByID: [initial.id: Self.stats(title: "Initial", tokens: 100)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        #expect(provider.parseCalls() == 1)
        #expect(store.summary(for: .allTime).totalTokens == 100)

        provider.update(
            sessions: [appended],
            statsByID: [:],
            appendResultsByID: [
                appended.id: Self.appendResult(for: appended, tokens: 25, at: Date(timeIntervalSince1970: 1_050)),
            ]
        )

        await store.refresh()

        #expect(provider.parseCalls() == 1)
        #expect(provider.appendCalls() == 1)
        #expect(store.summary(for: .allTime).totalTokens == 125)
        #expect(store.sessions.first?.stats?.messageCount == 2)
    }

    @MainActor
    @Test("Duplicate appended usage events do not double charge but still advance parse state")
    func duplicateAppendedEventsAdvanceParseStateWithoutDoubleCharging() async {
        let initial = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 100)
        let appended = Self.session(lastModified: Date(timeIntervalSince1970: 1_060), fileSize: 160)
        let ledger = Self.temporaryLedger()
        let provider = MutableSessionProvider(
            sessions: [initial],
            statsByID: [initial.id: Self.stats(title: "Initial", tokens: 100)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: ledger
        )

        await store.refresh()
        let duplicate = Self.appendResult(
            for: appended,
            eventKey: "Initial-event",
            tokens: 25,
            at: Date(timeIntervalSince1970: 1_050)
        )
        provider.update(
            sessions: [appended],
            statsByID: [:],
            appendResultsByID: [appended.id: duplicate]
        )

        await store.refresh()

        let parseState = await ledger.parseState(for: appended.id)
        #expect(store.summary(for: .allTime).totalTokens == 100)
        #expect(parseState?.eventCount == 2)
    }

    @MainActor
    @Test("Shrunk or rewritten session replaces ledger events instead of accumulating")
    func shrunkSessionRebuildsLedgerEvents() async {
        let original = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 100)
        let rewritten = Self.session(lastModified: Date(timeIntervalSince1970: 1_100), fileSize: 50)
        let provider = MutableSessionProvider(
            sessions: [original],
            statsByID: [original.id: Self.stats(title: "Original", tokens: 100)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        #expect(store.summary(for: .allTime).totalTokens == 100)

        provider.update(
            sessions: [rewritten],
            statsByID: [rewritten.id: Self.stats(title: "Rewritten", tokens: 40)]
        )

        await store.refresh()

        #expect(provider.parseCalls() == 2)
        #expect(provider.appendCalls() == 0)
        #expect(store.summary(for: .allTime).totalTokens == 40)
        #expect(store.sessions.first?.stats?.title == "Rewritten")
    }

    @MainActor
    @Test("Temporary parse failure hides session but preserves ledger totals and retries")
    func temporaryParseFailurePreservesLedgerTotalsAndRetries() async {
        let original = Self.session(lastModified: Date(timeIntervalSince1970: 1_000), fileSize: 100)
        let unreadable = Self.session(lastModified: Date(timeIntervalSince1970: 1_100), fileSize: 120)
        let recovered = Self.session(lastModified: Date(timeIntervalSince1970: 1_100), fileSize: 120)
        let provider = MutableSessionProvider(
            sessions: [original],
            statsByID: [original.id: Self.stats(title: "Original", tokens: 100)]
        )
        let store = SessionStore(
            registry: ProviderRegistry(providers: [provider]),
            pricing: TestPricing.table,
            usageLedger: Self.temporaryLedger()
        )

        await store.refresh()
        #expect(store.sessions.count == 1)
        #expect(store.summary(for: .allTime).totalTokens == 100)

        provider.update(sessions: [unreadable], statsByID: [:])
        await store.refresh()

        #expect(store.sessions.isEmpty)
        #expect(store.summary(for: .allTime).totalTokens == 100)

        provider.update(
            sessions: [recovered],
            statsByID: [recovered.id: Self.stats(title: "Recovered", tokens: 120)]
        )
        await store.refresh()

        #expect(provider.parseCalls() == 3)
        #expect(store.sessions.first?.stats?.title == "Recovered")
        #expect(store.summary(for: .allTime).totalTokens == 120)
    }

    private static func session(
        id: String = "project::session",
        externalID: String = "session",
        lastModified: Date,
        fileSize: Int64,
        cwd: String? = "/tmp/project",
        agentInfo: SessionAgentInfo? = nil
    ) -> Session {
        Session(
            id: id,
            externalID: externalID,
            provider: .codex,
            projectDirectoryName: "project",
            filePath: "/tmp/\(externalID).jsonl",
            cwd: cwd,
            lastModified: lastModified,
            fileSize: fileSize,
            stats: nil,
            agentInfo: agentInfo
        )
    }

    private static func appendResult(
        for session: Session,
        eventKey: String? = nil,
        tokens: Int,
        at timestamp: Date
    ) -> UsageLedgerAppendResult {
        let usage = TokenUsage(
            inputTokens: tokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreation5mTokens: 0,
            cacheCreation1hTokens: 0
        )
        let cost = CostEstimate(standardAPI: Double(tokens) / 1_000_000)
        let event = UsageLedgerEvent(
            eventKey: eventKey ?? "\(session.id)-append-\(Int(timestamp.timeIntervalSince1970))",
            sessionID: session.id,
            provider: session.provider,
            model: "model-a",
            timestamp: timestamp,
            usage: usage,
            cost: cost,
            sourcePath: session.filePath,
            sequenceIndex: 1,
            parentSessionID: session.agentInfo?.parentSessionID
        )
        return UsageLedgerAppendResult(
            events: [event],
            lastParsedByteOffset: UInt64(max(session.fileSize, 0)),
            messageCountDelta: 1,
            firstActivity: timestamp,
            lastActivity: timestamp,
            title: nil,
            lastModel: "model-a"
        )
    }

    private static func stats(
        title: String,
        tokens: Int = 0,
        cost explicitCost: Double? = nil,
        at timestamp: Date = Date(timeIntervalSince1970: 1_000)
    ) -> SessionStats {
        let usage = TokenUsage(
            inputTokens: tokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreation5mTokens: 0,
            cacheCreation1hTokens: 0
        )
        let cost = CostEstimate(standardAPI: explicitCost ?? Double(tokens) / 1_000_000)
        let model = ModelUsage(model: "model-a", messageCount: 1, usage: usage, costEstimate: cost)
        SessionStats(
            title: title,
            messageCount: 1,
            firstActivity: timestamp,
            lastActivity: timestamp,
            models: tokens > 0 ? [model] : [],
            timeline: tokens > 0 ? [ModelBucket(model: "model-a", start: timestamp, usage: usage)] : [],
            billableMessages: tokens > 0
                ? [BillableMessage(hash: "\(title)-event", model: "model-a", usage: usage, cost: cost, timestamp: timestamp)]
                : []
        )
    }

    private static func message(id: String, text: String) -> SessionTranscriptMessage {
        SessionTranscriptMessage(
            id: id,
            role: .assistant,
            text: text,
            timestamp: Date(timeIntervalSince1970: 2_000),
            model: "model-a"
        )
    }

    private static func temporaryLedger() -> UsageLedgerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stats-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("usage-ledger.json", isDirectory: false)
        return UsageLedgerStore(fileURL: url)
    }

    private static func temporaryDeletedStore() -> DeletedSessionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stats-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("deleted-sessions.json", isDirectory: false)
        return DeletedSessionStore(fileURL: url)
    }
}

private final class MutableSessionProvider: Provider, @unchecked Sendable {
    let kind: ProviderKind = .codex
    var dataDirectoryExists: Bool { true }

    private let lock = NSLock()
    private var sessions: [Session]
    private var statsByID: [String: SessionStats]
    private var appendResultsByID: [String: UsageLedgerAppendResult]
    private var messagesByID: [String: [SessionTranscriptMessage]]
    private var parseCallCount = 0
    private var appendCallCount = 0

    init(
        sessions: [Session],
        statsByID: [String: SessionStats],
        appendResultsByID: [String: UsageLedgerAppendResult] = [:],
        messagesByID: [String: [SessionTranscriptMessage]] = [:]
    ) {
        self.sessions = sessions
        self.statsByID = statsByID
        self.appendResultsByID = appendResultsByID
        self.messagesByID = messagesByID
    }

    func update(
        sessions: [Session],
        statsByID: [String: SessionStats],
        appendResultsByID: [String: UsageLedgerAppendResult] = [:],
        messagesByID: [String: [SessionTranscriptMessage]] = [:]
    ) {
        lock.withLock {
            self.sessions = sessions
            self.statsByID = statsByID
            self.appendResultsByID = appendResultsByID
            self.messagesByID = messagesByID
        }
    }

    func parseCalls() -> Int {
        lock.withLock { parseCallCount }
    }

    func appendCalls() -> Int {
        lock.withLock { appendCallCount }
    }

    func discoverSessions() async -> [Session] {
        lock.withLock { sessions }
    }

    func parse(_ session: Session) async -> SessionStats? {
        lock.withLock {
            parseCallCount += 1
            return statsByID[session.id]
        }
    }

    func parseUsageAppend(_ session: Session, from state: UsageLedgerParseState) async -> UsageLedgerAppendResult? {
        lock.withLock {
            appendCallCount += 1
            return appendResultsByID[session.id]
        }
    }

    func transcriptMessages(for session: Session) async -> [SessionTranscriptMessage] {
        lock.withLock { messagesByID[session.id] ?? [] }
    }
}
