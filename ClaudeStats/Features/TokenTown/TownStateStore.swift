import Foundation

protocol TownStateStoring: Sendable {
    func readState() async -> TownState
    func writeState(_ state: TownState) async
}

actor TownStateStore: TownStateStoring {
    static let currentSchemaVersion = TownState.currentSchemaVersion

    private let directory: URL
    private let schemaVersion: Int

    init(directory: URL? = nil, schemaVersion: Int = TownStateStore.currentSchemaVersion) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.directory = base
                .appendingPathComponent("Claude Stats", isDirectory: true)
                .appendingPathComponent("TokenTown", isDirectory: true)
                .appendingPathComponent("v\(schemaVersion)", isDirectory: true)
        }
        self.schemaVersion = schemaVersion
    }

    func readState() async -> TownState {
        guard FileManager.default.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL) else {
            return .empty
        }
        do {
            let state = try decoder.decode(TownState.self, from: data)
            guard state.schemaVersion == schemaVersion else { return .empty }
            return state
        } catch {
            Log.store.error("Token Town state decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    func writeState(_ state: TownState) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var next = state
            next.schemaVersion = schemaVersion
            let data = try encoder.encode(next)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            Log.store.error("Token Town state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var stateURL: URL {
        directory.appendingPathComponent("state.json", isDirectory: false)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
