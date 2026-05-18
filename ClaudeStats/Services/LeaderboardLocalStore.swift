import CryptoKit
import Foundation

protocol LeaderboardLocalStoring: Sendable {
    func readScores(for key: LeaderboardScoresCacheKey) async -> LeaderboardCachedScores?
    func writeScores(_ scores: [LeaderboardScore], for key: LeaderboardScoresCacheKey, savedAt: Date) async
    func readHistory(for key: LeaderboardHistoryCacheKey) async -> LeaderboardCachedHistory?
    func writeHistory(_ points: [LeaderboardScoreHistoryPoint], for key: LeaderboardHistoryCacheKey, savedAt: Date) async
    func readProfile(userHash: String) async -> LeaderboardCachedProfile?
    func writeProfile(_ profile: LeaderboardProfile, savedAt: Date) async
    func readSyncState() async -> LeaderboardLocalSyncState
    func writeSyncState(_ state: LeaderboardLocalSyncState) async
}

struct LeaderboardScoresCacheKey: Codable, Hashable, Sendable {
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let periodKey: String
    let limit: Int

    var digest: String {
        Self.sha256([
            metric.rawValue,
            period.rawValue,
            periodKey,
            "\(limit)",
        ].joined(separator: "|"))
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct LeaderboardHistoryCacheKey: Codable, Hashable, Sendable {
    let userHash: String
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let windowKeys: [String]

    var digest: String {
        Self.sha256([
            userHash,
            metric.rawValue,
            period.rawValue,
            windowKeys.joined(separator: ","),
        ].joined(separator: "|"))
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct LeaderboardProfileCacheKey: Codable, Hashable, Sendable {
    let userHash: String

    var digest: String {
        let digest = SHA256.hash(data: Data(userHash.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct LeaderboardCachedScores: Codable, Equatable, Sendable {
    let key: LeaderboardScoresCacheKey
    let savedAt: Date
    let scores: [LeaderboardScore]
}

struct LeaderboardCachedHistory: Codable, Equatable, Sendable {
    let key: LeaderboardHistoryCacheKey
    let savedAt: Date
    let points: [LeaderboardScoreHistoryPoint]
}

struct LeaderboardCachedProfile: Codable, Equatable, Sendable {
    let key: LeaderboardProfileCacheKey
    let savedAt: Date
    let profile: LeaderboardProfile
}

struct LeaderboardLocalSyncState: Codable, Equatable, Sendable {
    var lastFingerprint: String?
    var lastUploadedAt: Date?
    var lastSubmittedPeriodKeys: [String]

    static let empty = LeaderboardLocalSyncState(
        lastFingerprint: nil,
        lastUploadedAt: nil,
        lastSubmittedPeriodKeys: []
    )
}

actor LeaderboardLocalStore: LeaderboardLocalStoring {
    static let currentSchemaVersion = 1

    private enum Bucket: String {
        case scores
        case history
        case profiles
    }

    private struct Envelope<Key: Codable & Equatable & Sendable, Payload: Codable & Sendable>: Codable, Sendable {
        let schemaVersion: Int
        let key: Key
        let savedAt: Date
        let payload: Payload
    }

    private struct SyncStateEnvelope: Codable, Sendable {
        let schemaVersion: Int
        let state: LeaderboardLocalSyncState
    }

    private let directory: URL
    private let schemaVersion: Int

    init(directory: URL? = nil, schemaVersion: Int = LeaderboardLocalStore.currentSchemaVersion) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.directory = base
                .appendingPathComponent("Claude Stats", isDirectory: true)
                .appendingPathComponent("Leaderboards", isDirectory: true)
                .appendingPathComponent("v\(schemaVersion)", isDirectory: true)
        }
        self.schemaVersion = schemaVersion
    }

    func readScores(for key: LeaderboardScoresCacheKey) async -> LeaderboardCachedScores? {
        guard let envelope: Envelope<LeaderboardScoresCacheKey, [LeaderboardScore]> = read(bucket: .scores, key: key) else {
            return nil
        }
        return LeaderboardCachedScores(key: envelope.key, savedAt: envelope.savedAt, scores: envelope.payload)
    }

    func writeScores(_ scores: [LeaderboardScore], for key: LeaderboardScoresCacheKey, savedAt: Date = .now) async {
        write(scores, bucket: .scores, key: key, savedAt: savedAt)
    }

    func readHistory(for key: LeaderboardHistoryCacheKey) async -> LeaderboardCachedHistory? {
        guard let envelope: Envelope<LeaderboardHistoryCacheKey, [LeaderboardScoreHistoryPoint]> = read(bucket: .history, key: key) else {
            return nil
        }
        return LeaderboardCachedHistory(key: envelope.key, savedAt: envelope.savedAt, points: envelope.payload)
    }

    func writeHistory(_ points: [LeaderboardScoreHistoryPoint], for key: LeaderboardHistoryCacheKey, savedAt: Date = .now) async {
        write(points, bucket: .history, key: key, savedAt: savedAt)
    }

    func readProfile(userHash: String) async -> LeaderboardCachedProfile? {
        let key = LeaderboardProfileCacheKey(userHash: userHash)
        guard let envelope: Envelope<LeaderboardProfileCacheKey, LeaderboardProfile> = read(bucket: .profiles, key: key) else {
            return nil
        }
        return LeaderboardCachedProfile(key: envelope.key, savedAt: envelope.savedAt, profile: envelope.payload)
    }

    func writeProfile(_ profile: LeaderboardProfile, savedAt: Date = .now) async {
        write(profile, bucket: .profiles, key: LeaderboardProfileCacheKey(userHash: profile.userHash), savedAt: savedAt)
    }

    func readSyncState() async -> LeaderboardLocalSyncState {
        guard FileManager.default.fileExists(atPath: syncStateURL.path),
              let data = try? Data(contentsOf: syncStateURL) else {
            return .empty
        }
        do {
            let envelope = try decoder.decode(SyncStateEnvelope.self, from: data)
            guard envelope.schemaVersion == schemaVersion else { return .empty }
            return envelope.state
        } catch {
            Log.network.error("Leaderboard sync state decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    func writeSyncState(_ state: LeaderboardLocalSyncState) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let envelope = SyncStateEnvelope(schemaVersion: schemaVersion, state: state)
            let data = try encoder.encode(envelope)
            try data.write(to: syncStateURL, options: .atomic)
        } catch {
            Log.network.error("Leaderboard sync state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func read<Key: Codable & Equatable & Sendable, Payload: Codable & Sendable>(
        bucket: Bucket,
        key: Key
    ) -> Envelope<Key, Payload>? {
        let url = fileURL(bucket: bucket, digest: digest(for: key))
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let envelope = try decoder.decode(Envelope<Key, Payload>.self, from: data)
            guard envelope.schemaVersion == schemaVersion, envelope.key == key else { return nil }
            return envelope
        } catch {
            Log.network.error("Leaderboard cache decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<Key: Codable & Equatable & Sendable, Payload: Codable & Sendable>(
        _ payload: Payload,
        bucket: Bucket,
        key: Key,
        savedAt: Date
    ) {
        do {
            let bucketDirectory = directory.appendingPathComponent(bucket.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: bucketDirectory, withIntermediateDirectories: true)
            let envelope = Envelope(schemaVersion: schemaVersion, key: key, savedAt: savedAt, payload: payload)
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL(bucket: bucket, digest: digest(for: key)), options: .atomic)
        } catch {
            Log.network.error("Leaderboard cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(bucket: Bucket, digest: String) -> URL {
        directory
            .appendingPathComponent(bucket.rawValue, isDirectory: true)
            .appendingPathComponent(digest)
            .appendingPathExtension("json")
    }

    private var syncStateURL: URL {
        directory.appendingPathComponent("sync-state.json", isDirectory: false)
    }

    private func digest<Key: Encodable>(for key: Key) -> String {
        if let key = key as? LeaderboardScoresCacheKey {
            return key.digest
        }
        if let key = key as? LeaderboardHistoryCacheKey {
            return key.digest
        }
        if let key = key as? LeaderboardProfileCacheKey {
            return key.digest
        }
        let data = (try? encoder.encode(key)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
