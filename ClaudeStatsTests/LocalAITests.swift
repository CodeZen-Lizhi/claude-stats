import Foundation
import Testing
@testable import ClaudeStats

@Suite("Local AI model catalog")
struct LocalAIModelCatalogTests {
    @Test("Built-in manifests are Codable and preserve embedding metadata")
    func manifestRoundTrip() throws {
        let model = try #require(LocalAIModelCatalog.builtInModels.first)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(LocalAIModelManifest.self, from: data)

        #expect(decoded.id == "multilingual-e5-small-gguf-q8")
        #expect(decoded.runtime == .llamaGGUF)
        #expect(decoded.dimensions == 384)
        #expect(decoded.pooling == .mean)
    }

    @Test("Recommendation keeps low-memory Apple Silicon Macs on small model")
    func recommendedModelForSmallMemory() {
        #expect(LocalAIModelCatalog.recommendedModelID(memoryBytes: 8 * 1_073_741_824) == "multilingual-e5-small-gguf-q8")
    }

    @Test("Recommendation prefers base on Apple Silicon with enough memory")
    func recommendedModelForLargeMemory() {
        #expect(LocalAIModelCatalog.recommendedModelID(memoryBytes: 16 * 1_073_741_824) == "multilingual-e5-base-gguf-q8")
    }
}

@Suite("Local AI file verification")
struct LocalAIModelFileVerifierTests {
    @Test("SHA-256 verifier reports mismatches")
    func checksumMismatch() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.gguf")
        try Data("fixture".utf8).write(to: file)

        #expect(throws: LocalAIModelStoreError.self) {
            try LocalAIModelFileVerifier.verifySHA256(fileURL: file, expected: String(repeating: "0", count: 64))
        }
    }
}

@Suite("Transcript embedding index")
struct TranscriptEmbeddingIndexTests {
    @Test("Vector blobs round-trip and cosine search ranks best session")
    func vectorRoundTripAndRanking() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = TranscriptEmbeddingIndex(url: root.appendingPathComponent("embeddings.sqlite"))

        try await index.replaceChunks(
            provider: .claude,
            sessionID: "s1",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            dimensions: 3,
            chunks: [
                TranscriptEmbeddingChunk(
                    sessionID: "s1",
                    chunkID: "chunk-0",
                    textHash: "hash-a",
                    excerpt: "SwiftUI settings work",
                    vector: [1, 0, 0]
                ),
                TranscriptEmbeddingChunk(
                    sessionID: "s1",
                    chunkID: "chunk-1",
                    textHash: "hash-b",
                    excerpt: "Local embedding cache",
                    vector: [0.8, 0.2, 0]
                ),
            ]
        )
        try await index.replaceChunks(
            provider: .claude,
            sessionID: "s2",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            dimensions: 3,
            chunks: [
                TranscriptEmbeddingChunk(
                    sessionID: "s2",
                    chunkID: "chunk-0",
                    textHash: "hash-c",
                    excerpt: "Network proxy traces",
                    vector: [0, 1, 0]
                ),
            ]
        )

        let cached = try await index.cachedChunkHashes(
            provider: .claude,
            sessionID: "s1",
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker"
        )
        #expect(cached == ["chunk-0": "hash-a", "chunk-1": "hash-b"])

        let hits = try await index.search(
            provider: .claude,
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            queryVector: [1, 0, 0],
            limit: 2
        )
        #expect(hits.map(\.sessionID) == ["s1", "s2"])
        #expect(hits.first?.excerpt == "SwiftUI settings work")

        let excludingCurrent = try await index.search(
            provider: .claude,
            modelID: "multilingual-e5-small-gguf-q8",
            modelRevision: "gguf-q8-v1",
            chunkerVersion: "test-chunker",
            queryVector: [1, 0, 0],
            limit: 2,
            excludingSessionID: "s1"
        )
        #expect(excludingCurrent.map(\.sessionID) == ["s2"])
    }
}
