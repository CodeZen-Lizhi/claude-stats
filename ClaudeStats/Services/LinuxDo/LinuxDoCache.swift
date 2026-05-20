import Foundation

protocol LinuxDoCaching: Sendable {
    func readTopicList(feed: LinuxDoFeed, ttl: TimeInterval, now: Date) -> (list: LinuxDoTopicList, isStale: Bool)?
    func writeTopicList(_ list: LinuxDoTopicList, feed: LinuxDoFeed) throws
    func readCategories(ttl: TimeInterval, now: Date) -> (categories: [LinuxDoCategory], isStale: Bool)?
    func writeCategories(_ categories: [LinuxDoCategory], now: Date) throws
    func readTopic(id: Int, ttl: TimeInterval, now: Date) -> (detail: LinuxDoTopicDetail, isStale: Bool)?
    func writeTopic(_ detail: LinuxDoTopicDetail) throws
    func clear() throws
}

struct LinuxDoCache: LinuxDoCaching {
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let bundleID = Bundle.main.bundleIdentifier ?? "com.claudestats.ClaudeStats"
            self.rootURL = caches
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("linuxdo", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        }
    }

    func readTopicList(feed: LinuxDoFeed, ttl: TimeInterval, now: Date = .now) -> (list: LinuxDoTopicList, isStale: Bool)? {
        guard let result = read(LinuxDoTopicList.self, path: "lists/\(safe(feed.key)).json", ttl: ttl, now: now) else {
            return nil
        }
        return (result.value, result.isStale)
    }

    func writeTopicList(_ list: LinuxDoTopicList, feed: LinuxDoFeed) throws {
        try write(list, path: "lists/\(safe(feed.key)).json")
    }

    func readCategories(ttl: TimeInterval = 24 * 60 * 60, now: Date = .now) -> (categories: [LinuxDoCategory], isStale: Bool)? {
        guard let result = read(CategoriesEnvelope.self, path: "categories.json", ttl: ttl, now: now) else { return nil }
        return (result.value.categories, result.isStale)
    }

    func writeCategories(_ categories: [LinuxDoCategory], now: Date = .now) throws {
        try write(CategoriesEnvelope(categories: categories, fetchedAt: now), path: "categories.json")
    }

    func readTopic(id: Int, ttl: TimeInterval = 15 * 60, now: Date = .now) -> (detail: LinuxDoTopicDetail, isStale: Bool)? {
        guard let result = read(LinuxDoTopicDetail.self, path: "topics/\(id).json", ttl: ttl, now: now) else {
            return nil
        }
        return (result.value, result.isStale)
    }

    func writeTopic(_ detail: LinuxDoTopicDetail) throws {
        try write(detail, path: "topics/\(detail.id).json")
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
    }

    private func read<T: Codable & Sendable>(
        _ type: T.Type,
        path: String,
        ttl: TimeInterval,
        now: Date
    ) -> (value: T, isStale: Bool)? {
        let fileURL = rootURL.appendingPathComponent(path, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let envelope = try decoder.decode(CacheEnvelope<T>.self, from: data)
            guard envelope.schemaVersion == 1 else { return nil }
            return (envelope.payload, now.timeIntervalSince(envelope.savedAt) > ttl)
        } catch {
            Log.app.error("LinuxDo cache decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<T: Codable & Sendable>(_ value: T, path: String, now: Date = .now) throws {
        let fileURL = rootURL.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let envelope = CacheEnvelope(schemaVersion: 1, savedAt: now, payload: value)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    private func safe(_ raw: String) -> String {
        raw.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    private struct CacheEnvelope<T: Codable & Sendable>: Codable, Sendable {
        let schemaVersion: Int
        let savedAt: Date
        let payload: T
    }

    private struct CategoriesEnvelope: Codable, Sendable {
        let categories: [LinuxDoCategory]
        let fetchedAt: Date
    }
}
