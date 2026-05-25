import CryptoKit
import Foundation

struct TranscriptEmbeddingChunk: Sendable, Hashable {
    let sessionID: String
    let chunkID: String
    let textHash: String
    let excerpt: String
    let vector: [Float]
}

struct TranscriptEmbeddingSearchHit: Sendable, Hashable {
    let sessionID: String
    let score: Double
    let excerpt: String
}

actor TranscriptEmbeddingIndex {
    private let url: URL
    private var connection: SQLiteConnection?

    init(url: URL = TranscriptAnalysisPaths.embeddingIndexURL()) {
        self.url = url
    }

    func cachedChunkHashes(
        provider: ProviderKind,
        sessionID: String,
        modelID: String,
        modelRevision: String,
        chunkerVersion: String
    ) throws -> [String: String] {
        let connection = try openConnection()
        let statement = try connection.prepare(
            """
            SELECT chunk_id, text_hash
            FROM embedding_chunks
            WHERE provider = ? AND session_id = ? AND model_id = ? AND model_revision = ? AND chunker_version = ?
            """
        )
        defer { statement.reset() }
        try statement.bind(provider.rawValue, at: 1)
        try statement.bind(sessionID, at: 2)
        try statement.bind(modelID, at: 3)
        try statement.bind(modelRevision, at: 4)
        try statement.bind(chunkerVersion, at: 5)
        var rows: [String: String] = [:]
        while try statement.step() {
            guard let chunkID = statement.columnString(0),
                  let textHash = statement.columnString(1) else { continue }
            rows[chunkID] = textHash
        }
        return rows
    }

    func replaceChunks(
        provider: ProviderKind,
        sessionID: String,
        modelID: String,
        modelRevision: String,
        chunkerVersion: String,
        dimensions: Int,
        chunks: [TranscriptEmbeddingChunk]
    ) throws {
        let connection = try openConnection()
        try connection.transaction {
            let delete = try connection.prepare(
                """
                DELETE FROM embedding_chunks
                WHERE provider = ? AND session_id = ? AND model_id = ? AND model_revision = ? AND chunker_version = ?
                """
            )
            try delete.bind(provider.rawValue, at: 1)
            try delete.bind(sessionID, at: 2)
            try delete.bind(modelID, at: 3)
            try delete.bind(modelRevision, at: 4)
            try delete.bind(chunkerVersion, at: 5)
            try delete.finish()

            let insert = try connection.prepare(
                """
                INSERT INTO embedding_chunks (
                    provider, session_id, chunk_id, model_id, model_revision, chunker_version,
                    text_hash, dimensions, vector, excerpt, saved_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            for chunk in chunks {
                try insert.bind(provider.rawValue, at: 1)
                try insert.bind(sessionID, at: 2)
                try insert.bind(chunk.chunkID, at: 3)
                try insert.bind(modelID, at: 4)
                try insert.bind(modelRevision, at: 5)
                try insert.bind(chunkerVersion, at: 6)
                try insert.bind(chunk.textHash, at: 7)
                try insert.bind(dimensions, at: 8)
                try insert.bind(Self.data(from: chunk.vector), at: 9)
                try insert.bind(chunk.excerpt, at: 10)
                try insert.bind(Date().timeIntervalSinceReferenceDate, at: 11)
                try insert.finish()
                insert.reset()
            }
        }
    }

    func search(
        provider: ProviderKind,
        modelID: String,
        modelRevision: String,
        chunkerVersion: String,
        queryVector: [Float],
        limit: Int,
        excludingSessionID: String? = nil
    ) throws -> [TranscriptEmbeddingSearchHit] {
        let connection = try openConnection()
        let statement = try connection.prepare(
            """
            SELECT session_id, vector, excerpt
            FROM embedding_chunks
            WHERE provider = ? AND model_id = ? AND model_revision = ? AND chunker_version = ?
            """
        )
        defer { statement.reset() }
        try statement.bind(provider.rawValue, at: 1)
        try statement.bind(modelID, at: 2)
        try statement.bind(modelRevision, at: 3)
        try statement.bind(chunkerVersion, at: 4)

        var bestBySession: [String: TranscriptEmbeddingSearchHit] = [:]
        while try statement.step() {
            guard let sessionID = statement.columnString(0),
                  sessionID != excludingSessionID,
                  let data = statement.columnData(1),
                  let excerpt = statement.columnString(2) else { continue }
            let vector = Self.vector(from: data)
            guard vector.count == queryVector.count else { continue }
            let score = Self.cosine(queryVector, vector)
            if let existing = bestBySession[sessionID], existing.score >= score {
                continue
            }
            bestBySession[sessionID] = TranscriptEmbeddingSearchHit(
                sessionID: sessionID,
                score: score,
                excerpt: excerpt
            )
        }
        return Array(bestBySession.values)
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func deleteAll() throws {
        let connection = try openConnection()
        try connection.execute("DELETE FROM embedding_chunks")
    }

    private func openConnection() throws -> SQLiteConnection {
        if let connection { return connection }
        let connection = try SQLiteConnection(url: url)
        try configure(connection)
        self.connection = connection
        return connection
    }

    private func configure(_ connection: SQLiteConnection) throws {
        try connection.execute("PRAGMA journal_mode=WAL")
        try connection.execute("PRAGMA synchronous=NORMAL")
        try connection.execute("PRAGMA busy_timeout=2500")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS embedding_chunks (
                provider TEXT NOT NULL,
                session_id TEXT NOT NULL,
                chunk_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                model_revision TEXT NOT NULL,
                chunker_version TEXT NOT NULL,
                text_hash TEXT NOT NULL,
                dimensions INTEGER NOT NULL,
                vector BLOB NOT NULL,
                excerpt TEXT NOT NULL,
                saved_at REAL NOT NULL,
                PRIMARY KEY (provider, session_id, chunk_id, model_id, model_revision, chunker_version)
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_embedding_chunks_search
            ON embedding_chunks (provider, model_id, model_revision, chunker_version);
            """
        )
    }

    static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return Data() }
            return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.stride)
        }
    }

    private static func vector(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: Float.self).baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: base, count: count))
        }
    }

    private static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var dot: Double = 0
        var lhsNorm: Double = 0
        var rhsNorm: Double = 0
        for index in lhs.indices {
            let a = Double(lhs[index])
            let b = Double(rhs[index])
            dot += a * b
            lhsNorm += a * a
            rhsNorm += b * b
        }
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }
}
