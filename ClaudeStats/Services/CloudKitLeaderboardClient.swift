import CloudKit
import CryptoKit
import Foundation
import Security

enum LeaderboardCloudAccountState: Sendable, Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case unavailable(String)

    var displayText: String {
        switch self {
        case .unknown: "Not checked"
        case .available: "iCloud available"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud restricted"
        case .unavailable(let reason): reason
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum LeaderboardCloudError: Error, Sendable, CustomStringConvertible {
    case missingEntitlement(String)
    case noAccount
    case restricted
    case userRecordUnavailable
    case partialFailure(String)
    case cloudKit(String)

    var description: String {
        switch self {
        case .missingEntitlement(let reason): reason
        case .noAccount: "Sign in to iCloud to use leaderboards."
        case .restricted: "iCloud access is restricted on this Mac."
        case .userRecordUnavailable: "Could not identify the iCloud user."
        case .partialFailure(let reason): reason
        case .cloudKit(let reason): reason
        }
    }
}

protocol LeaderboardCloudServicing: Sendable {
    func accountState() async -> LeaderboardCloudAccountState
    func submit(_ submissions: [LeaderboardSubmission]) async throws
    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int) async throws -> [LeaderboardScore]
}

enum CloudKitLeaderboardConfig {
    static let containerIdentifier = "iCloud.com.claudestats.ClaudeStats"
    static let recordType = "LeaderboardScoreV1"
    static let providerScope = "all"
}

enum CloudKitRuntimeEntitlements {
    private static let applicationIdentifierKey = "com.apple.application-identifier"
    private static let iCloudServicesKey = "com.apple.developer.icloud-services"
    private static let iCloudContainersKey = "com.apple.developer.icloud-container-identifiers"

    static func hasCloudKitAccess(containerIdentifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let applicationIdentifier = entitlementValue(applicationIdentifierKey, task: task) as? String,
              !applicationIdentifier.isEmpty,
              let services = entitlementValue(iCloudServicesKey, task: task) as? [String],
              services.contains("CloudKit"),
              let containers = entitlementValue(iCloudContainersKey, task: task) as? [String],
              containers.contains(containerIdentifier) else {
            return false
        }
        return true
    }

    private static func entitlementValue(_ key: String, task: SecTask) -> Any? {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
}

enum CloudKitLeaderboardRecordMapper {
    static let salt = "com.claudestats.leaderboards.v1"
    private static let profileMetric = "profile"
    private static let profilePeriod = "profile"
    private static let profilePeriodKey = "profile"

    enum Field {
        static let userHash = "userHash"
        static let nickname = "nickname"
        static let metric = "metric"
        static let period = "period"
        static let periodKey = "periodKey"
        static let score = "score"
        static let providerScope = "providerScope"
        static let periodStartUTC = "periodStartUTC"
        static let periodEndUTC = "periodEndUTC"
        static let appVersion = "appVersion"
        static let updatedAt = "updatedAt"
    }

    static let desiredKeys = [
        Field.userHash,
        Field.nickname,
        Field.metric,
        Field.period,
        Field.periodKey,
        Field.score,
        Field.updatedAt,
    ]

    static let profileDesiredKeys = [
        Field.userHash,
        Field.nickname,
        Field.updatedAt,
    ]

    static func userHash(forUserRecordName recordName: String) -> String {
        let digest = SHA256.hash(data: Data("\(recordName):\(salt)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func recordName(userHash: String,
                           metric: LeaderboardMetric,
                           period: LeaderboardPeriod,
                           periodKey: String) -> String {
        "score_v1_\(userHash)_\(metric.rawValue)_\(period.rawValue)_\(periodKey)"
    }

    static func record(from submission: LeaderboardSubmission, userHash: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName(
            userHash: userHash,
            metric: submission.metric,
            period: submission.period,
            periodKey: submission.periodKey
        ))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[Field.userHash] = userHash
        record[Field.nickname] = submission.nickname
        record[Field.metric] = submission.metric.rawValue
        record[Field.period] = submission.period.rawValue
        record[Field.periodKey] = submission.periodKey
        record[Field.score] = NSNumber(value: submission.score)
        record[Field.providerScope] = CloudKitLeaderboardConfig.providerScope
        record[Field.periodStartUTC] = submission.periodStartUTC as NSDate
        if let periodEndUTC = submission.periodEndUTC {
            record[Field.periodEndUTC] = periodEndUTC as NSDate
        }
        record[Field.appVersion] = submission.appVersion
        record[Field.updatedAt] = submission.updatedAt as NSDate
        return record
    }

    static func profileRecordName(userHash: String) -> String {
        "profile_v1_\(userHash)"
    }

    static func profileRecord(userHash: String,
                              nickname: String,
                              appVersion: String,
                              updatedAt: Date) -> CKRecord {
        let recordID = CKRecord.ID(recordName: profileRecordName(userHash: userHash))
        let record = CKRecord(recordType: CloudKitLeaderboardConfig.recordType, recordID: recordID)
        record[Field.userHash] = userHash
        record[Field.nickname] = nickname
        record[Field.metric] = profileMetric
        record[Field.period] = profilePeriod
        record[Field.periodKey] = profilePeriodKey
        record[Field.score] = NSNumber(value: 0)
        record[Field.providerScope] = CloudKitLeaderboardConfig.providerScope
        record[Field.periodStartUTC] = Date(timeIntervalSince1970: 0) as NSDate
        record[Field.appVersion] = appVersion
        record[Field.updatedAt] = updatedAt as NSDate
        return record
    }

    static func userHash(from record: CKRecord) -> String? {
        record[Field.userHash] as? String
    }

    static func profileNickname(from record: CKRecord) -> (userHash: String, nickname: String)? {
        guard let userHash = record[Field.userHash] as? String,
              let nickname = record[Field.nickname] as? String,
              !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (userHash, nickname)
    }

    static func score(from record: CKRecord, rank: Int) -> LeaderboardScore? {
        score(from: record, rank: rank, profileNickname: nil)
    }

    static func score(from record: CKRecord, rank: Int, profileNickname: String?) -> LeaderboardScore? {
        guard let metricRaw = record[Field.metric] as? String,
              let metric = LeaderboardMetric(rawValue: metricRaw),
              let periodRaw = record[Field.period] as? String,
              let period = LeaderboardPeriod(rawValue: periodRaw),
              let periodKey = record[Field.periodKey] as? String,
              let nickname = record[Field.nickname] as? String,
              let scoreNumber = record[Field.score] as? NSNumber else {
            return nil
        }
        let updatedAt = (record[Field.updatedAt] as? Date)
            ?? (record[Field.updatedAt] as? NSDate).map { $0 as Date }
            ?? record.modificationDate
            ?? Date(timeIntervalSince1970: 0)
        return LeaderboardScore(
            id: record.recordID.recordName,
            metric: metric,
            period: period,
            periodKey: periodKey,
            score: scoreNumber.int64Value,
            rank: rank,
            nickname: profileNickname ?? nickname,
            updatedAt: updatedAt
        )
    }
}

struct CloudKitLeaderboardClient: LeaderboardCloudServicing {
    private let containerIdentifier: String
    private let entitlementChecker: @Sendable (String) -> Bool

    init(containerIdentifier: String = CloudKitLeaderboardConfig.containerIdentifier,
         entitlementChecker: @escaping @Sendable (String) -> Bool = CloudKitRuntimeEntitlements.hasCloudKitAccess) {
        self.containerIdentifier = containerIdentifier
        self.entitlementChecker = entitlementChecker
    }

    func accountState() async -> LeaderboardCloudAccountState {
        guard entitlementChecker(containerIdentifier) else {
            return .unavailable(Self.missingEntitlementMessage)
        }
        do {
            let status = try await container.accountStatus()
            return Self.state(from: status)
        } catch {
            return .unavailable(Self.shortCloudKitMessage(error))
        }
    }

    func submit(_ submissions: [LeaderboardSubmission]) async throws {
        guard !submissions.isEmpty else { return }
        try ensureCloudKitEntitlement()
        let status = try await container.accountStatus()
        switch Self.state(from: status) {
        case .available:
            break
        case .noAccount:
            throw LeaderboardCloudError.noAccount
        case .restricted:
            throw LeaderboardCloudError.restricted
        case .unknown, .unavailable:
            throw LeaderboardCloudError.cloudKit("iCloud is not available right now.")
        }

        let userRecordName = try await container.userRecordID().recordName
        let userHash = CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: userRecordName)
        let profileRecord = CloudKitLeaderboardRecordMapper.profileRecord(
            userHash: userHash,
            nickname: submissions[0].nickname,
            appVersion: submissions[0].appVersion,
            updatedAt: Date()
        )
        let records = [profileRecord] + submissions.map {
            CloudKitLeaderboardRecordMapper.record(from: $0, userHash: userHash)
        }
        let result = try await publicDatabase.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
        let failures = result.saveResults.compactMap { _, value -> String? in
            if case .failure(let error) = value {
                return Self.shortCloudKitMessage(error)
            }
            return nil
        }
        if let first = failures.first {
            throw LeaderboardCloudError.partialFailure(first)
        }
    }

    func fetchScores(metric: LeaderboardMetric,
                     period: LeaderboardPeriod,
                     periodKey: String,
                     limit: Int = 100) async throws -> [LeaderboardScore] {
        try ensureCloudKitEntitlement()
        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %@",
            CloudKitLeaderboardRecordMapper.Field.metric, metric.rawValue,
            CloudKitLeaderboardRecordMapper.Field.period, period.rawValue,
            CloudKitLeaderboardRecordMapper.Field.periodKey, periodKey,
            CloudKitLeaderboardRecordMapper.Field.providerScope, CloudKitLeaderboardConfig.providerScope
        )
        let query = CKQuery(recordType: CloudKitLeaderboardConfig.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: CloudKitLeaderboardRecordMapper.Field.score, ascending: false),
            NSSortDescriptor(key: CloudKitLeaderboardRecordMapper.Field.updatedAt, ascending: true),
        ]
        do {
            let result = try await publicDatabase.records(
                matching: query,
                desiredKeys: CloudKitLeaderboardRecordMapper.desiredKeys,
                resultsLimit: limit
            )
            let records = result.matchResults
                .compactMap { try? $0.1.get() }
            let profileNicknames = await profileNicknames(for: records)
            return records
                .enumerated()
                .compactMap { index, record in
                    let userHash = CloudKitLeaderboardRecordMapper.userHash(from: record)
                    return CloudKitLeaderboardRecordMapper.score(
                        from: record,
                        rank: index + 1,
                        profileNickname: userHash.flatMap { profileNicknames[$0] }
                    )
                }
        } catch {
            throw LeaderboardCloudError.cloudKit(Self.shortCloudKitMessage(error))
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var publicDatabase: CKDatabase {
        container.publicCloudDatabase
    }

    private func profileNicknames(for records: [CKRecord]) async -> [String: String] {
        let userHashes = records
            .compactMap(CloudKitLeaderboardRecordMapper.userHash(from:))
            .uniqued()
        guard !userHashes.isEmpty else { return [:] }

        let profileIDs = userHashes.map {
            CKRecord.ID(recordName: CloudKitLeaderboardRecordMapper.profileRecordName(userHash: $0))
        }
        do {
            let results = try await publicDatabase.records(
                for: profileIDs,
                desiredKeys: CloudKitLeaderboardRecordMapper.profileDesiredKeys
            )
            return results.values.reduce(into: [:]) { partial, result in
                guard case .success(let record) = result,
                      let profile = CloudKitLeaderboardRecordMapper.profileNickname(from: record) else {
                    return
                }
                partial[profile.userHash] = profile.nickname
            }
        } catch {
            Log.network.error("Leaderboard profile lookup failed: \(Self.shortCloudKitMessage(error), privacy: .public)")
            return [:]
        }
    }

    private func ensureCloudKitEntitlement() throws {
        guard entitlementChecker(containerIdentifier) else {
            throw LeaderboardCloudError.missingEntitlement(Self.missingEntitlementMessage)
        }
    }

    private static let missingEntitlementMessage = "CloudKit entitlement is missing or incomplete in this build."

    private static func state(from status: CKAccountStatus) -> LeaderboardCloudAccountState {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .unavailable("Could not determine iCloud status.")
        case .temporarilyUnavailable:
            return .unavailable("iCloud is temporarily unavailable.")
        @unknown default:
            return .unavailable("Unsupported iCloud account state.")
        }
    }

    private static func shortCloudKitMessage(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return LeaderboardCloudError.noAccount.description
            case .networkUnavailable, .networkFailure:
                return "Network unavailable."
            case .serviceUnavailable, .requestRateLimited:
                return "CloudKit is temporarily unavailable."
            case .permissionFailure:
                return "CloudKit permission denied. Check the app's iCloud container."
            case .partialFailure:
                return "Some leaderboard records failed to save."
            case .serverRejectedRequest, .invalidArguments:
                return "CloudKit rejected the leaderboard request. Check schema and indexes."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
