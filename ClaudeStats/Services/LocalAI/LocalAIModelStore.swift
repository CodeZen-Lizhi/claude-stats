import CryptoKit
import Foundation
import Observation

enum LocalAIModelStoreError: Error, LocalizedError {
    case modelNotFound
    case missingDownloadURL
    case invalidHuggingFaceInput
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            "Model not found."
        case .missingDownloadURL:
            "This model does not have a downloadable artifact URL."
        case .invalidHuggingFaceInput:
            "Enter a Hugging Face repo and GGUF file name."
        case .checksumMismatch(let expected, let actual):
            "Model checksum mismatch. Expected \(expected), got \(actual)."
        }
    }
}

@MainActor
@Observable
final class LocalAIModelStore {
    private(set) var customModels: [LocalAIModelManifest] = []
    private(set) var installStates: [String: LocalModelInstallState] = [:]
    var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Keys.selectedModelID) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]

    var allModels: [LocalAIModelManifest] {
        LocalAIModelCatalog.builtInModels + customModels
    }

    var selectedModel: LocalAIModelManifest {
        model(id: selectedModelID)
            ?? model(id: LocalAIModelCatalog.recommendedModelID())
            ?? LocalAIModelCatalog.builtInModels[0]
    }

    var recommendedModelID: String {
        LocalAIModelCatalog.recommendedModelID()
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        stateURL: URL = LocalAIPaths.stateURL()
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.stateURL = stateURL
        self.selectedModelID = defaults.string(forKey: Keys.selectedModelID)
            ?? LocalAIModelCatalog.recommendedModelID()
        loadPersistedState()
    }

    func model(id: String) -> LocalAIModelManifest? {
        allModels.first { $0.id == id }
    }

    func installState(for modelID: String) -> LocalModelInstallState {
        installStates[modelID] ?? .notInstalled(modelID: modelID)
    }

    func installedModelURL(for model: LocalAIModelManifest) -> URL? {
        let state = installState(for: model.id)
        guard state.phase == .installed,
              let path = state.installedPath,
              fileManager.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func download(modelID: String, huggingFaceToken: String? = nil) {
        guard downloadTasks[modelID] == nil else { return }
        guard let model = model(id: modelID) else {
            installStates[modelID] = failedState(modelID: modelID, message: LocalAIModelStoreError.modelNotFound.localizedDescription)
            persistState()
            return
        }

        installStates[modelID] = LocalModelInstallState(
            modelID: modelID,
            phase: .downloading,
            installedPath: nil,
            bytesReceived: 0,
            byteCount: model.artifact.byteCount,
            errorMessage: nil,
            installedAt: nil
        )
        persistState()

        downloadTasks[modelID] = Task { [weak self] in
            do {
                guard let self else { return }
                let installedURL = try await LocalAIModelDownloader.download(
                    model: model,
                    huggingFaceToken: huggingFaceToken,
                    progress: { [weak self] bytesReceived, byteCount in
                        await MainActor.run {
                            guard let self else { return }
                            var state = self.installStates[modelID] ?? .notInstalled(modelID: modelID)
                            state.phase = .downloading
                            state.bytesReceived = bytesReceived
                            state.byteCount = byteCount ?? state.byteCount
                            self.installStates[modelID] = state
                        }
                    }
                )
                await MainActor.run {
                    self.installStates[modelID] = LocalModelInstallState(
                        modelID: modelID,
                        phase: .installed,
                        installedPath: installedURL.path,
                        bytesReceived: (try? installedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? model.artifact.byteCount ?? 0,
                        byteCount: model.artifact.byteCount,
                        errorMessage: nil,
                        installedAt: Date()
                    )
                    self.downloadTasks[modelID] = nil
                    self.persistState()
                }
            } catch {
                await MainActor.run {
                    self?.installStates[modelID] = self?.failedState(modelID: modelID, message: error.localizedDescription)
                    self?.downloadTasks[modelID] = nil
                    self?.persistState()
                }
            }
        }
    }

    func addHuggingFaceModel(repo: String, file: String, revision: String, token: String?) {
        let trimmedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFile = file.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRevision = revision.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "main"
        guard !trimmedRepo.isEmpty, trimmedFile.hasSuffix(".gguf") else {
            let id = "custom-invalid"
            installStates[id] = failedState(modelID: id, message: LocalAIModelStoreError.invalidHuggingFaceInput.localizedDescription)
            return
        }

        let id = "hf-\(Self.sha256("\(trimmedRepo)|\(trimmedFile)|\(trimmedRevision)").prefix(16))"
        let model = LocalAIModelManifest(
            id: id,
            displayName: trimmedFile.replacingOccurrences(of: ".gguf", with: ""),
            subtitle: trimmedRepo,
            kind: .embedding,
            runtime: .llamaGGUF,
            modelRevision: trimmedRevision,
            sourceRepo: trimmedRepo,
            sourceRevision: trimmedRevision,
            artifact: .huggingFace(repo: trimmedRepo, file: trimmedFile, revision: trimmedRevision),
            licenseName: "Custom",
            licenseURL: URL(string: "https://huggingface.co/\(trimmedRepo)"),
            dimensions: 384,
            maxTokens: 512,
            minMemoryGB: 8,
            parameterCount: "Custom",
            pooling: .mean,
            recommendedTier: "Custom",
            isExperimental: true
        )
        if !customModels.contains(where: { $0.id == id }) {
            customModels.append(model)
        }
        selectedModelID = id
        persistState()
        download(modelID: id, huggingFaceToken: token?.nonEmpty)
    }

    func delete(modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        if let path = installStates[modelID]?.installedPath {
            try? fileManager.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
        }
        installStates[modelID] = .notInstalled(modelID: modelID)
        persistState()
    }

    private func failedState(modelID: String, message: String?) -> LocalModelInstallState {
        LocalModelInstallState(
            modelID: modelID,
            phase: .failed,
            installedPath: nil,
            bytesReceived: 0,
            byteCount: model(id: modelID)?.artifact.byteCount,
            errorMessage: message,
            installedAt: nil
        )
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        customModels = payload.customModels
        installStates = Dictionary(uniqueKeysWithValues: payload.installStates.map { ($0.modelID, $0) })
    }

    private func persistState() {
        do {
            try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = PersistedState(customModels: customModels, installStates: Array(installStates.values))
            let data = try JSONEncoder.pretty.encode(payload)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            Log.app.error("Local AI model state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct PersistedState: Codable {
        let customModels: [LocalAIModelManifest]
        let installStates: [LocalModelInstallState]
    }

    private enum Keys {
        static let selectedModelID = "localAI.selectedModelID"
    }
}

private enum LocalAIModelDownloader {
    static func download(
        model: LocalAIModelManifest,
        huggingFaceToken: String?,
        progress: @escaping @Sendable (Int64, Int64?) async -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let sourceURL = try downloadURL(for: model)
        let installDirectory = LocalAIPaths.modelsDirectory(fileManager: fileManager)
            .appendingPathComponent(model.installDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let partialURL = installDirectory.appendingPathComponent(model.fileName + ".partial")
        let finalURL = installDirectory.appendingPathComponent(model.fileName)
        if fileManager.fileExists(atPath: finalURL.path) {
            if let expected = model.artifact.sha256?.lowercased(), !expected.isEmpty {
                let actual = try await Task.detached(priority: .utility) {
                    try LocalAIModelFileVerifier.sha256Hex(fileURL: finalURL)
                }.value
                if actual == expected {
                    return finalURL
                }
            } else {
                return finalURL
            }
        }

        var existingBytes: Int64 = 0
        if fileManager.fileExists(atPath: partialURL.path) {
            existingBytes = Int64((try partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        } else {
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }

        var request = URLRequest(url: sourceURL)
        request.setValue("ClaudeStats/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", forHTTPHeaderField: "User-Agent")
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        if model.artifact.sourceKind == .huggingFace, let huggingFaceToken, !huggingFaceToken.isEmpty {
            request.setValue("Bearer \(huggingFaceToken)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            if existingBytes > 0, http.statusCode != 206 {
                try Data().write(to: partialURL, options: .atomic)
                existingBytes = 0
            }
        }

        let responseLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let expectedTotal = model.artifact.byteCount ?? responseLength.map { existingBytes + $0 }
        await progress(existingBytes, expectedTotal)

        let handle = try FileHandle(forWritingTo: partialURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var received = existingBytes
        var lastPublished = existingBytes
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: Data(buffer))
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if received - lastPublished >= 512 * 1024 {
                    await progress(received, expectedTotal)
                    lastPublished = received
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
            received += Int64(buffer.count)
        }
        await progress(received, expectedTotal)

        if let expected = model.artifact.sha256?.lowercased(), !expected.isEmpty {
            let actual = try await Task.detached(priority: .utility) {
                try LocalAIModelFileVerifier.sha256Hex(fileURL: partialURL)
            }.value
            guard actual == expected else {
                throw LocalAIModelStoreError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        try fileManager.moveItem(at: partialURL, to: finalURL)
        return finalURL
    }

    private static func downloadURL(for model: LocalAIModelManifest) throws -> URL {
        switch model.artifact.sourceKind {
        case .githubRelease:
            guard let url = model.artifact.url else { throw LocalAIModelStoreError.missingDownloadURL }
            return url
        case .huggingFace:
            guard let repo = model.artifact.huggingFaceRepo,
                  let file = model.artifact.huggingFaceFile else {
                throw LocalAIModelStoreError.invalidHuggingFaceInput
            }
            let revision = model.artifact.huggingFaceRevision ?? "main"
            guard let encodedFile = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(encodedFile)") else {
                throw LocalAIModelStoreError.invalidHuggingFaceInput
            }
            return url
        }
    }

}

enum LocalAIModelFileVerifier {
    static func verifySHA256(fileURL: URL, expected: String) throws {
        let actual = try sha256Hex(fileURL: fileURL)
        guard actual == expected.lowercased() else {
            throw LocalAIModelStoreError.checksumMismatch(expected: expected.lowercased(), actual: actual)
        }
    }

    static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
