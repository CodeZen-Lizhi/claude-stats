import Foundation

/// One persisted billable token event. These records are the source of truth
/// for aggregate usage so deleting old transcripts does not erase history.
struct UsageLedgerEvent: Sendable, Hashable, Codable, Identifiable {
    let eventKey: String
    let sessionID: String
    let provider: ProviderKind
    let model: String
    let timestamp: Date
    let usage: TokenUsage
    let cost: CostEstimate
    let sourcePath: String
    let sequenceIndex: Int
    var parentSessionID: String?

    var id: String { eventKey }
}

/// Persisted parser progress for one transcript file.
struct UsageLedgerParseState: Sendable, Hashable, Codable {
    let sessionID: String
    let provider: ProviderKind
    let sourcePath: String
    var fileSize: Int64
    var lastModified: Date
    var lastParsedByteOffset: UInt64
    var eventCount: Int
    var title: String?
    var messageCount: Int
    var firstActivity: Date?
    var lastActivity: Date?
    var sourceExists: Bool
    var lastSeenAt: Date
    var lastModel: String?
    var hasViewableTranscript: Bool? = nil
}

/// Provider parse result for bytes appended after a previously parsed offset.
struct UsageLedgerAppendResult: Sendable, Hashable {
    let events: [UsageLedgerEvent]
    let lastParsedByteOffset: UInt64
    let messageCountDelta: Int
    let firstActivity: Date?
    let lastActivity: Date?
    let title: String?
    let lastModel: String?
}

/// On-disk usage ledger payload. Kept as one JSON envelope for now; the data
/// volume is modest and this avoids adding a migration-heavy database layer.
struct UsageLedgerSnapshot: Sendable, Hashable, Codable {
    var version: Int = 1
    var events: [UsageLedgerEvent] = []
    var parseStates: [UsageLedgerParseState] = []
}

enum UsageLedgerPaths {
    private static let appSupportFolderName = "Codex Statistics"
    private static let usageLedgerFolderName = "UsageLedger"

    static func directory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(usageLedgerFolderName, isDirectory: true)
    }

    static func ledgerURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager)
            .appendingPathComponent("usage-ledger.json", isDirectory: false)
    }
}
