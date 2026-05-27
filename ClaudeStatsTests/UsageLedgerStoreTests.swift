import Foundation
import Testing
@testable import ClaudeStats

@Suite("Usage ledger store")
struct UsageLedgerStoreTests {
    @Test("Marking unchanged live sessions does not rewrite the ledger")
    func markingUnchangedLiveSessionsDoesNotRewriteLedger() async throws {
        let url = Self.temporaryLedgerURL()
        let ledger = UsageLedgerStore(fileURL: url)
        let session = Self.session()
        let firstSeenAt = Date(timeIntervalSince1970: 1_000)

        await ledger.replaceEvents(for: session, stats: Self.stats(), now: firstSeenAt)
        let initialData = try Data(contentsOf: url)

        await ledger.markSeen([session], now: Date(timeIntervalSince1970: 2_000))

        let afterMarkSeenData = try Data(contentsOf: url)
        let parseState = await ledger.parseState(for: session.id)
        #expect(afterMarkSeenData == initialData)
        #expect(parseState?.lastSeenAt == firstSeenAt)
    }

    @Test("Batched persistence flushes pending ledger changes at the end")
    func batchedPersistenceFlushesPendingLedgerChangesAtEnd() async throws {
        let url = Self.temporaryLedgerURL()
        let ledger = UsageLedgerStore(fileURL: url)

        await ledger.beginPersistenceBatch()
        await ledger.replaceEvents(for: Self.session(id: "project::one", externalID: "one"), stats: Self.stats(title: "One"))
        await ledger.replaceEvents(for: Self.session(id: "project::two", externalID: "two"), stats: Self.stats(title: "Two"))
        #expect(FileManager.default.fileExists(atPath: url.path) == false)

        await ledger.endPersistenceBatch()

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageLedgerSnapshot.self, from: data)
        #expect(snapshot.parseStates.map(\.sessionID).sorted() == ["project::one", "project::two"])
    }

    private static func temporaryLedgerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stats-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("usage-ledger.json", isDirectory: false)
    }

    private static func session(
        id: String = "project::session",
        externalID: String = "session"
    ) -> Session {
        Session(
            id: id,
            externalID: externalID,
            provider: .codex,
            projectDirectoryName: "project",
            filePath: "/tmp/\(externalID).jsonl",
            cwd: "/tmp/project",
            lastModified: Date(timeIntervalSince1970: 1_000),
            fileSize: 100
        )
    }

    private static func stats(title: String = "Session") -> SessionStats {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let usage = TokenUsage(
            inputTokens: 100,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreation5mTokens: 0,
            cacheCreation1hTokens: 0
        )
        let cost = CostEstimate(standardAPI: 0.0001)
        return SessionStats(
            title: title,
            messageCount: 1,
            firstActivity: timestamp,
            lastActivity: timestamp,
            models: [ModelUsage(model: "model-a", messageCount: 1, usage: usage, costEstimate: cost)],
            timeline: [ModelBucket(model: "model-a", start: timestamp, usage: usage)],
            billableMessages: [
                BillableMessage(hash: "\(title)-event", model: "model-a", usage: usage, cost: cost, timestamp: timestamp),
            ]
        )
    }
}
