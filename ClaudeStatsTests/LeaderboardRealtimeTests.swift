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

    @Test("Global subscription ID is stable and managed")
    func globalSubscriptionIDIsStable() {
        let notification = LeaderboardRealtimeNotification(subscriptionID: LeaderboardRealtimeNotification.globalSubscriptionID)

        #expect(LeaderboardRealtimeNotification.globalSubscriptionID == "leaderboard.score.v2.all")
        #expect(notification.isGlobalScoreChange)
        #expect(notification.scope == nil)
        #expect(LeaderboardRealtimeNotification.isManagedSubscriptionID(LeaderboardRealtimeNotification.globalSubscriptionID))
    }

    @Test("Legacy scoped subscriptions remain managed")
    func legacyScopedSubscriptionsRemainManaged() {
        let scope = LeaderboardRealtimeScope(metric: .activityMinutes, period: .week, periodKey: "2026-W20")
        let notification = LeaderboardRealtimeNotification(subscriptionID: scope.subscriptionID)

        #expect(!notification.isGlobalScoreChange)
        #expect(notification.scope == scope)
        #expect(LeaderboardRealtimeNotification.isManagedSubscriptionID(scope.subscriptionID))
        #expect(!LeaderboardRealtimeNotification.isManagedSubscriptionID("leaderboard.score.v2.other"))
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

    @Test("Subscription predicate targets all leaderboard score changes without window fields")
    func subscriptionPredicateTargetsAllScoreChanges() {
        let predicate = CloudKitLeaderboardSubscriptionClient.subscriptionPredicate().predicateFormat

        #expect(predicate.contains("providerScope"))
        #expect(predicate.contains("all"))
        #expect(!predicate.contains("metric"))
        #expect(!predicate.contains("tokensWithoutCacheRead"))
        #expect(!predicate.contains("periodKey"))
        #expect(!predicate.contains("2026-05"))
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
