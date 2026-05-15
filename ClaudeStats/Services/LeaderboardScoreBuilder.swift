import Foundation

struct LeaderboardScoreBuilder: Sendable {
    func submissions(sessions: [Session],
                     nickname: String,
                     includeActivity: Bool,
                     now: Date = .now,
                     appVersion: String = Self.appVersion) -> [LeaderboardSubmission] {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return [] }

        let windows = LeaderboardPeriodCalculator.windows(now: now)
        return windows.flatMap { window in
            submissions(
                sessions: sessions,
                nickname: trimmedNickname,
                includeActivity: includeActivity,
                window: window,
                now: now,
                appVersion: appVersion
            )
        }
    }

    func submissions(sessions: [Session],
                     nickname: String,
                     includeActivity: Bool,
                     window: LeaderboardPeriodWindow,
                     now: Date = .now,
                     appVersion: String = Self.appVersion) -> [LeaderboardSubmission] {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return [] }

        var out: [LeaderboardSubmission] = []
        let usage = tokenUsage(in: sessions, window: window)
        append(.tokensWithCache, score: Int64(usage.total), to: &out,
               nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)
        append(.tokensWithoutCacheRead, score: Int64(usage.total(includingCacheRead: false)), to: &out,
               nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)

        if includeActivity {
            let minutes = Int64(activitySeconds(in: sessions, window: window) / 60)
            append(.activityMinutes, score: minutes, to: &out,
                   nickname: trimmedNickname, window: window, now: now, appVersion: appVersion)
        }
        return out
    }

    private func tokenUsage(in sessions: [Session], window: LeaderboardPeriodWindow) -> TokenUsage {
        sessions.reduce(.zero) { partial, session in
            guard let stats = session.stats else { return partial }
            let when = stats.lastActivity ?? session.lastModified
            guard window.contains(when) else { return partial }
            return partial + stats.totalUsage
        }
    }

    private func activitySeconds(in sessions: [Session], window: LeaderboardPeriodWindow) -> Int {
        let boundsEnd = window.endUTC ?? Date.distantFuture
        let bounds = DateInterval(start: window.startUTC, end: boundsEnd)
        let intervals = sessions
            .flatMap { $0.stats?.activityIntervals ?? [] }
            .compactMap { ActivityAnalyzer.clip($0, to: bounds) }
        return Int(ActivityAnalyzer.totalDuration(ActivityAnalyzer.union(intervals)))
    }

    private func append(_ metric: LeaderboardMetric,
                        score: Int64,
                        to submissions: inout [LeaderboardSubmission],
                        nickname: String,
                        window: LeaderboardPeriodWindow,
                        now: Date,
                        appVersion: String) {
        guard score > 0 else { return }
        submissions.append(LeaderboardSubmission(
            metric: metric,
            period: window.period,
            periodKey: window.periodKey,
            score: score,
            nickname: nickname,
            periodStartUTC: window.startUTC,
            periodEndUTC: window.endUTC,
            appVersion: appVersion,
            updatedAt: now
        ))
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
