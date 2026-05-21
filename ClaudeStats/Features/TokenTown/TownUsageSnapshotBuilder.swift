import Foundation

enum TownUsageSnapshotBuilder {
    static func make(
        provider: ProviderKind,
        period: StatsPeriod,
        sessions: [Session],
        pricing: ModelPricing,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TownUsageSnapshot {
        let providerSessions = sessions.filter { $0.provider == provider && $0.stats != nil }
        let periodSessions = providerSessions.filter { session in
            let when = session.stats?.lastActivity ?? session.lastModified
            return period.contains(when, now: now, calendar: calendar)
        }
        let summary = UsageSummary.make(period: period, sessions: providerSessions, pricing: pricing, now: now, calendar: calendar)
        let todaySummary = UsageSummary.make(period: .today, sessions: providerSessions, pricing: pricing, now: now, calendar: calendar)

        var projectTotals: [String: (tokens: Int, sessions: Int)] = [:]
        for session in periodSessions {
            let name = sanitizedProjectName(session.projectDisplayName)
            var effective = 0
            for model in session.stats?.models ?? [] {
                effective += effectiveTokens(model.usage)
            }
            let current = projectTotals[name] ?? (tokens: 0, sessions: 0)
            projectTotals[name] = (tokens: current.tokens + effective, sessions: current.sessions + 1)
        }
        var projectRows: [TownProjectUsage] = []
        for (name, total) in projectTotals {
            projectRows.append(TownProjectUsage(name: name, effectiveTokens: total.tokens, sessionCount: total.sessions))
        }
        projectRows.sort { lhs, rhs in
            if lhs.effectiveTokens == rhs.effectiveTokens { return lhs.name < rhs.name }
            return lhs.effectiveTokens > rhs.effectiveTokens
        }
        let projects = Array(projectRows.prefix(10))

        var models: [TownModelUsage] = []
        for model in summary.models {
            let effective = effectiveTokens(model.usage)
            if effective > 0 {
                models.append(TownModelUsage(model: model.model, effectiveTokens: effective))
            }
        }
        models.sort { lhs, rhs in
            if lhs.effectiveTokens == rhs.effectiveTokens { return lhs.model < rhs.model }
            return lhs.effectiveTokens > rhs.effectiveTokens
        }

        let unit: Calendar.Component = period == .today ? .hour : .day
        let rebucketed = summary.timeline.rebucketed(by: unit, calendar: calendar)
        let timelineBuckets = rebucketed.map { bucket in
            effectiveTokens(bucket.usage)
        }
        let totalUsage = summary.totalUsage
        let todayUsage = todaySummary.totalUsage

        return TownUsageSnapshot(
            provider: provider,
            period: period,
            sessionCount: periodSessions.count,
            messageCount: summary.messageCount,
            effectiveTokens: effectiveTokens(totalUsage),
            cacheReadTokens: totalUsage.cacheReadTokens,
            cacheCreationTokens: totalUsage.cacheCreationTotalTokens,
            outputTokens: totalUsage.outputTokens,
            todayEffectiveTokens: effectiveTokens(todayUsage),
            todayCacheReadTokens: todayUsage.cacheReadTokens,
            projects: projects,
            models: models,
            timelineBuckets: timelineBuckets
        )
    }

    static func effectiveTokens(_ usage: TokenUsage) -> Int {
        usage.inputTokens + usage.outputTokens + usage.cacheCreationTotalTokens
    }

    private static func sanitizedProjectName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Project" }
        let last = (trimmed as NSString).lastPathComponent
        let candidate = last.isEmpty ? trimmed : last
        return String(candidate.prefix(32))
    }
}
