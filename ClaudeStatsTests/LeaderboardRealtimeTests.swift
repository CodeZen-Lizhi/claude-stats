import Foundation
import Testing
@testable import ClaudeStats

@Suite("Leaderboard realtime")
struct LeaderboardRealtimeTests {
    @Test("Subscription ID round-trips scope fields")
    func subscriptionIDRoundTripsScope() {
        let scope = LeaderboardRealtimeScope(metric: .activityMinutes, period: .week, periodKey: "2026-W20")

        #expect(scope.subscriptionID == "leaderboard.score.v1.activityMinutes.week.2026-W20")
        #expect(LeaderboardRealtimeScope(subscriptionID: scope.subscriptionID) == scope)
        #expect(LeaderboardRealtimeScope(subscriptionID: "other.score.v1.activityMinutes.week.2026-W20") == nil)
    }

    @Test("Current windows are live and historical windows are not")
    func liveScopeMatchesCurrentWindowOnly() {
        let now = dateUTC(2026, 5, 16, 8)
        let today = LeaderboardPeriodCalculator.window(for: .day, now: now)
        let yesterday = LeaderboardPeriodCalculator.window(for: .day, now: now.addingTimeInterval(-86_400))

        #expect(LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .day, requestedWindow: today, now: now) != nil)
        #expect(LeaderboardRealtimeScope.liveScope(metric: .tokensWithCache, period: .day, requestedWindow: yesterday, now: now) == nil)
        #expect(LeaderboardRealtimeScope.liveScope(
            metric: .tokensWithCache,
            period: .allTime,
            requestedWindow: LeaderboardPeriodCalculator.window(for: .allTime, now: now),
            now: now
        ) != nil)
    }

    @Test("Subscription predicate targets score records for the active scope")
    func subscriptionPredicateTargetsActiveScope() {
        let scope = LeaderboardRealtimeScope(metric: .tokensWithoutCacheRead, period: .month, periodKey: "2026-05")
        let predicate = CloudKitLeaderboardSubscriptionClient.subscriptionPredicate(for: scope).predicateFormat

        #expect(predicate.contains("providerScope"))
        #expect(predicate.contains("all"))
        #expect(predicate.contains("metric"))
        #expect(predicate.contains("tokensWithoutCacheRead"))
        #expect(predicate.contains("period"))
        #expect(predicate.contains("month"))
        #expect(predicate.contains("periodKey"))
        #expect(predicate.contains("2026-05"))
    }

    private func dateUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
