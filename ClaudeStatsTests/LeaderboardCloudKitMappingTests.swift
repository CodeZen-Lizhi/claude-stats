import CloudKit
import Foundation
import Testing
@testable import ClaudeStats

@Suite("CloudKit leaderboard record mapping")
struct LeaderboardCloudKitMappingTests {
    @Test("User hash is deterministic and hides the raw CloudKit record name")
    func userHash() {
        let hash = CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: "_abc123")

        #expect(hash == CloudKitLeaderboardRecordMapper.userHash(forUserRecordName: "_abc123"))
        #expect(hash.count == 64)
        #expect(hash.contains("_abc123") == false)
    }

    @Test("Record name and fields are stable")
    func recordMapping() {
        let submission = LeaderboardSubmission(
            metric: .tokensWithoutCacheRead,
            period: .week,
            periodKey: "2026-W20",
            score: 42_000,
            nickname: "Ada",
            periodStartUTC: Date(timeIntervalSince1970: 1_768_176_000),
            periodEndUTC: Date(timeIntervalSince1970: 1_768_780_800),
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let record = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")

        #expect(record.recordID.recordName == "score_v1_userhash_tokensWithoutCacheRead_week_2026-W20")
        #expect(record.recordType == CloudKitLeaderboardConfig.recordType)
        #expect(record[CloudKitLeaderboardRecordMapper.Field.nickname] as? String == "Ada")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.metric] as? String == "tokensWithoutCacheRead")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.period] as? String == "week")
        #expect(record[CloudKitLeaderboardRecordMapper.Field.periodKey] as? String == "2026-W20")
        #expect((record[CloudKitLeaderboardRecordMapper.Field.score] as? NSNumber)?.int64Value == 42_000)
        #expect(record[CloudKitLeaderboardRecordMapper.Field.providerScope] as? String == "all")
    }

    @Test("CKRecord maps back to a Sendable score value")
    func scoreMapping() {
        let submission = LeaderboardSubmission(
            metric: .activityMinutes,
            period: .month,
            periodKey: "2026-05",
            score: 90,
            nickname: "Grace",
            periodStartUTC: Date(timeIntervalSince1970: 1_767_916_800),
            periodEndUTC: nil,
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let record = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")
        let score = CloudKitLeaderboardRecordMapper.score(from: record, rank: 7)

        #expect(score?.id == "score_v1_userhash_activityMinutes_month_2026-05")
        #expect(score?.metric == .activityMinutes)
        #expect(score?.period == .month)
        #expect(score?.periodKey == "2026-05")
        #expect(score?.score == 90)
        #expect(score?.rank == 7)
        #expect(score?.nickname == "Grace")
    }

    @Test("Profile nickname overrides the nickname stored on older score records")
    func profileNicknameOverridesScoreNickname() {
        let submission = LeaderboardSubmission(
            metric: .tokensWithCache,
            period: .day,
            periodKey: "2026-05-15",
            score: 100,
            nickname: "Old Name",
            periodStartUTC: Date(timeIntervalSince1970: 1_768_176_000),
            periodEndUTC: Date(timeIntervalSince1970: 1_768_262_400),
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_200_000)
        )
        let scoreRecord = CloudKitLeaderboardRecordMapper.record(from: submission, userHash: "userhash")
        let profile = CloudKitLeaderboardRecordMapper.profileRecord(
            userHash: "userhash",
            nickname: "New Name",
            appVersion: "1.2.3",
            updatedAt: Date(timeIntervalSince1970: 1_768_210_000)
        )

        #expect(CloudKitLeaderboardRecordMapper.profileRecordName(userHash: "userhash") == "profile_v1_userhash")
        #expect(CloudKitLeaderboardRecordMapper.profileNickname(from: profile)?.nickname == "New Name")
        #expect(CloudKitLeaderboardRecordMapper.userHash(from: scoreRecord) == "userhash")
        #expect(CloudKitLeaderboardRecordMapper.score(
            from: scoreRecord,
            rank: 1,
            profileNickname: "New Name"
        )?.nickname == "New Name")
    }

    @Test("Missing CloudKit entitlement is reported before touching CKContainer")
    func missingEntitlementShortCircuitsCloudKit() async {
        let client = CloudKitLeaderboardClient(entitlementChecker: { _ in false })
        let accountState = await client.accountState()

        #expect(accountState == .unavailable("CloudKit entitlement is missing or incomplete in this build."))

        do {
            _ = try await client.fetchScores(
                metric: .tokensWithCache,
                period: .day,
                periodKey: "2026-05-15",
                limit: 100
            )
            Issue.record("Expected missing entitlement error")
        } catch let error as LeaderboardCloudError {
            #expect(error.description == "CloudKit entitlement is missing or incomplete in this build.")
        } catch {
            Issue.record("Expected LeaderboardCloudError, got \(error)")
        }
    }
}
