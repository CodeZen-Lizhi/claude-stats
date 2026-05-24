import Foundation

enum LocalAIModelCatalog {
    static let githubReleaseBaseURL = URL(string: "https://github.com/1pitaph/Codex-stats-releases/releases/download/local-models-v1")!

    static let builtInModels: [LocalAIModelManifest] = [
        LocalAIModelManifest(
            id: "multilingual-e5-small-gguf-q8",
            displayName: "Multilingual E5 Small",
            subtitle: "Default semantic search model",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "intfloat/multilingual-e5-small",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("multilingual-e5-small-q8_0.gguf"),
                sha256: nil,
                byteCount: 132_000_000
            ),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/intfloat/multilingual-e5-small"),
            dimensions: 384,
            maxTokens: 512,
            minMemoryGB: 8,
            parameterCount: "0.1B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 8GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "multilingual-e5-base-gguf-q8",
            displayName: "Multilingual E5 Base",
            subtitle: "Balanced quality model",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "intfloat/multilingual-e5-base",
            sourceRevision: "main",
            artifact: .github(
                url: githubReleaseBaseURL.appendingPathComponent("multilingual-e5-base-q8_0.gguf"),
                sha256: nil,
                byteCount: 287_000_000
            ),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/intfloat/multilingual-e5-base"),
            dimensions: 768,
            maxTokens: 512,
            minMemoryGB: 16,
            parameterCount: "0.3B",
            pooling: .mean,
            recommendedTier: "Apple Silicon 16GB+",
            isExperimental: false
        ),
        LocalAIModelManifest(
            id: "bge-m3-gguf",
            displayName: "BGE M3",
            subtitle: "Phase 3 evaluation candidate",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "eval-v1",
            sourceRepo: "BAAI/bge-m3",
            sourceRevision: "main",
            artifact: .huggingFace(repo: "gpustack/bge-m3-GGUF", file: "bge-m3-Q8_0.gguf"),
            licenseName: "MIT",
            licenseURL: URL(string: "https://huggingface.co/BAAI/bge-m3"),
            dimensions: 1024,
            maxTokens: 8192,
            minMemoryGB: 16,
            parameterCount: "0.6B",
            pooling: .mean,
            recommendedTier: "Evaluation only",
            isExperimental: true
        ),
        LocalAIModelManifest(
            id: "qwen3-embedding-0_6b-gguf-q8",
            displayName: "Qwen3 Embedding 0.6B",
            subtitle: "Phase 3 multilingual/code candidate",
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: "gguf-q8-v1",
            sourceRepo: "Qwen/Qwen3-Embedding-0.6B",
            sourceRevision: "main",
            artifact: .huggingFace(
                repo: "Qwen/Qwen3-Embedding-0.6B-GGUF",
                file: "Qwen3-Embedding-0.6B-Q8_0.gguf"
            ),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B"),
            dimensions: 1024,
            maxTokens: 32_768,
            minMemoryGB: 16,
            parameterCount: "0.6B",
            pooling: .last,
            recommendedTier: "Evaluation only",
            isExperimental: true
        ),
    ]

    static func recommendedModelID(memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let memoryGB = Double(memoryBytes) / 1_073_741_824
        if memoryGB >= 15.5 {
            return "multilingual-e5-base-gguf-q8"
        }
        return "multilingual-e5-small-gguf-q8"
    }
}
