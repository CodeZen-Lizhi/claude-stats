import Foundation

enum LlamaEmbeddingEngineError: Error, LocalizedError {
    case modelNotInstalled
    case bridgeFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled: "The selected local model is not installed."
        case .bridgeFailed(let message): message
        case .invalidOutput: "The local embedding runtime returned invalid output."
        }
    }
}

actor LlamaEmbeddingEngine: EmbeddingEngine {
    let status: EmbeddingModelStatus = .ready
    let modelID: String
    let modelRevision: String
    let dimensions: Int
    let embedMode: EmbeddingMode = .llamaGGUF

    private let model: LocalAIModelManifest
    private let modelURL: URL
    private var bridge: LlamaEmbeddingBridge?

    init(model: LocalAIModelManifest, modelURL: URL) {
        self.model = model
        self.modelURL = modelURL
        self.modelID = model.id
        self.modelRevision = model.modelRevision
        self.dimensions = model.dimensions
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let runtime = try bridgeInstance()
        let rows: [[NSNumber]]
        do {
            rows = try runtime.embedTexts(texts)
        } catch {
            throw LlamaEmbeddingEngineError.bridgeFailed(error.localizedDescription)
        }
        return try rows.map { row in
            let vector = row.map { number in number.floatValue }
            guard vector.count == dimensions || dimensions == 0 else {
                throw LlamaEmbeddingEngineError.invalidOutput
            }
            return vector
        }
    }

    private func bridgeInstance() throws -> LlamaEmbeddingBridge {
        if let bridge { return bridge }
        let runtime: LlamaEmbeddingBridge
        do {
            runtime = try LlamaEmbeddingBridge(
                modelPath: modelURL.path,
                dimensions: model.dimensions,
                maxTokens: model.maxTokens,
                pooling: model.pooling.rawValue,
                useMetal: true
            )
        } catch {
            throw LlamaEmbeddingEngineError.bridgeFailed(error.localizedDescription)
        }
        bridge = runtime
        return runtime
    }
}

struct LocalAIEmbeddingEngineFactory: Sendable {
    func makeEngine(model: LocalAIModelManifest, modelURL: URL) -> any EmbeddingEngine {
        LlamaEmbeddingEngine(model: model, modelURL: modelURL)
    }
}
