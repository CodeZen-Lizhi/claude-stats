import Foundation

struct NetworkBodyReference: Identifiable, Sendable, Hashable, Codable {
    var id: UUID
    var byteCount: Int
    var contentType: String?
    var sha256: String
}

actor NetworkBodyStore {
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directoryURL = base.appendingPathComponent("ClaudeStats/Network/Bodies", isDirectory: true)
    }

    func write(_ data: Data, contentType: String?) throws -> NetworkBodyReference {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let id = UUID()
        let sha = Self.fnv1aHex(data)
        try data.write(to: url(for: id), options: .atomic)
        return NetworkBodyReference(id: id, byteCount: data.count, contentType: contentType, sha256: sha)
    }

    func read(_ reference: NetworkBodyReference) throws -> Data {
        try Data(contentsOf: url(for: reference.id))
    }

    func delete(_ reference: NetworkBodyReference) {
        try? FileManager.default.removeItem(at: url(for: reference.id))
    }

    private func url(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("body")
    }

    private static func fnv1aHex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
