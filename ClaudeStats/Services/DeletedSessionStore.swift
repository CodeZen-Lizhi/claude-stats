import Foundation

struct DeletedSessionRecord: Codable, Hashable, Identifiable, Sendable {
    var id: String { sessionID }

    let sessionID: String
    let externalID: String
    let provider: ProviderKind
    let projectDirectoryName: String
    let projectDisplayNameOverride: String?
    let filePath: String
    let cwd: String?
    let titleFallback: String?
    let sourceKind: SessionSourceKind
    let lastModified: Date
    let fileSize: Int64
    let agentInfo: SessionAgentInfo?
    let childSessionIDs: [String]
    let deletedAt: Date

    init(session: Session, deletedAt: Date) {
        self.sessionID = session.id
        self.externalID = session.externalID
        self.provider = session.provider
        self.projectDirectoryName = session.projectDirectoryName
        self.projectDisplayNameOverride = session.projectDisplayNameOverride
        self.filePath = session.filePath
        self.cwd = session.cwd
        self.titleFallback = session.titleFallback
        self.sourceKind = session.sourceKind
        self.lastModified = session.lastModified
        self.fileSize = session.fileSize
        self.agentInfo = session.agentInfo
        self.childSessionIDs = session.childSessions.map(\.id)
        self.deletedAt = deletedAt
    }

    func session(stats: SessionStats?) -> Session {
        Session(
            id: sessionID,
            externalID: externalID,
            provider: provider,
            projectDirectoryName: projectDirectoryName,
            projectDisplayNameOverride: projectDisplayNameOverride,
            filePath: filePath,
            cwd: cwd,
            titleFallback: titleFallback,
            sourceKind: sourceKind,
            lastModified: lastModified,
            fileSize: fileSize,
            stats: stats,
            agentInfo: agentInfo
        )
    }
}

struct DeletedSessionSnapshot: Codable, Sendable {
    var version: Int = 1
    var records: [DeletedSessionRecord] = []
}

actor DeletedSessionStore {
    private let fileURL: URL
    private var recordsByID: [String: DeletedSessionRecord]

    init(fileURL: URL = DeletedSessionPaths.recordsURL()) {
        self.fileURL = fileURL
        self.recordsByID = Dictionary(uniqueKeysWithValues: Self.load(from: fileURL).records.map { ($0.sessionID, $0) })
    }

    func records() -> [DeletedSessionRecord] {
        recordsByID.values.sorted { $0.deletedAt > $1.deletedAt }
    }

    func contains(_ session: Session) -> Bool {
        if recordsByID[session.id] != nil { return true }
        return recordsByID.values.contains { $0.filePath == session.filePath }
    }

    func add(_ records: [DeletedSessionRecord]) throws {
        for record in records {
            recordsByID[record.sessionID] = record
        }
        try persist()
    }

    func remove(sessionIDs: Set<String>) throws {
        for id in sessionIDs {
            recordsByID.removeValue(forKey: id)
        }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snapshot = DeletedSessionSnapshot(records: records())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> DeletedSessionSnapshot {
        guard let data = try? Data(contentsOf: url) else { return DeletedSessionSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(DeletedSessionSnapshot.self, from: data)) ?? DeletedSessionSnapshot()
    }
}

enum DeletedSessionPaths {
    private static let appSupportFolderName = "Codex Statistics"
    private static let deletedSessionsFolderName = "DeletedSessions"

    static func directory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(deletedSessionsFolderName, isDirectory: true)
    }

    static func recordsURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager)
            .appendingPathComponent("deleted-sessions.json", isDirectory: false)
    }
}

struct SessionDeletionFailure: Sendable, Hashable {
    let sessionID: String
    let title: String
    let message: String
}

struct SessionDeletionResult: Sendable, Hashable {
    let deletedIDs: Set<String>
    let failures: [SessionDeletionFailure]

    var deletedCount: Int { deletedIDs.count }
    var failedCount: Int { failures.count }
    var didDeleteAny: Bool { !deletedIDs.isEmpty }
    var firstFailureMessage: String? { failures.first?.message }
}
