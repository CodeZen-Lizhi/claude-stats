import Foundation
import Testing
@testable import ClaudeStats

@Suite("FloatingProviderStatusAdapters")
struct FloatingProviderStatusAdapterTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Claude floating status targets Claude Code and trims to 30 days")
    func claudeTargetsClaudeCode() throws {
        let snapshot = ClaudeStatusSnapshot(
            pageName: "Claude",
            pageUpdatedAt: nil,
            rollup: ClaudeStatusRollup(severity: .majorOutage, description: "Major outage"),
            components: [
                ClaudeStatusComponent(
                    id: ClaudeStatusComponentCatalog.claudeAIID,
                    name: "claude.ai",
                    status: .majorOutage,
                    updatedAt: nil,
                    position: 1
                ),
                ClaudeStatusComponent(
                    id: ClaudeStatusComponentCatalog.claudeCodeID,
                    name: "Claude Code",
                    status: .operational,
                    updatedAt: nil,
                    position: 2
                ),
            ],
            incidents: [],
            scheduledMaintenances: [],
            fetchedAt: baseDate
        )
        let uptime = ClaudeStatusUptimeSnapshot(
            histories: [
                ClaudeStatusComponentCatalog.claudeAIID: claudeHistory(
                    componentID: ClaudeStatusComponentCatalog.claudeAIID,
                    componentName: "claude.ai"
                ),
                ClaudeStatusComponentCatalog.claudeCodeID: claudeHistory(
                    componentID: ClaudeStatusComponentCatalog.claudeCodeID,
                    componentName: "Claude Code"
                ),
            ],
            fetchedAt: baseDate
        )

        let summary = try #require(ClaudeFloatingStatusAdapter.summary(snapshot: snapshot, uptimeSnapshot: uptime))
        #expect(summary.id == "claude:\(ClaudeStatusComponentCatalog.claudeCodeID)")
        #expect(summary.title == "Claude Code")
        #expect(summary.statusText == "Operational")
        #expect(summary.days.count == 30)
        #expect(summary.days.first?.date == date(offset: 15))
    }

    @Test("Codex floating status targets Codex group and trims to 30 days")
    func codexTargetsCodexGroup() throws {
        let components = [
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.chatGPTLoginID,
                name: "Login",
                status: .fullOutage,
                updatedAt: nil,
                position: 1
            ),
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.codexWebID,
                name: "Codex Web",
                status: .degradedPerformance,
                updatedAt: nil,
                position: 2
            ),
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.codexCLIID,
                name: "CLI",
                status: .operational,
                updatedAt: nil,
                position: 3
            ),
        ]
        let groups = OpenAIStatusGroupCatalog.groups(from: components)
        let snapshot = OpenAIStatusSnapshot(
            pageName: "OpenAI",
            pageUpdatedAt: nil,
            rollup: OpenAIStatusRollup(severity: .fullOutage, description: "Major outage"),
            groups: groups,
            components: components,
            incidents: [],
            scheduledMaintenances: [],
            fetchedAt: baseDate
        )
        let uptime = OpenAIStatusUptimeSnapshot(
            histories: [
                OpenAIStatusGroupCatalog.chatGPTID: openAIHistory(
                    groupID: OpenAIStatusGroupCatalog.chatGPTID,
                    groupName: "ChatGPT"
                ),
                OpenAIStatusGroupCatalog.codexID: openAIHistory(
                    groupID: OpenAIStatusGroupCatalog.codexID,
                    groupName: "Codex"
                ),
            ],
            groupDefinitions: OpenAIStatusGroupCatalog.defaultGroupDefinitions,
            fetchedAt: baseDate
        )

        let summary = try #require(OpenAIFloatingStatusAdapter.summary(snapshot: snapshot, uptimeSnapshot: uptime))
        #expect(summary.id == "openai:\(OpenAIStatusGroupCatalog.codexID)")
        #expect(summary.title == "Codex")
        #expect(summary.statusText == "Degraded Performance")
        #expect(summary.days.count == 30)
        #expect(summary.days.first?.date == date(offset: 15))
    }

    private func claudeHistory(componentID: String, componentName: String) -> ClaudeStatusUptimeHistory {
        ClaudeStatusUptimeHistory(
            componentID: componentID,
            componentName: componentName,
            startDate: nil,
            days: (0..<45).map { index in
                ClaudeStatusUptimeDay(
                    date: date(offset: index),
                    partialOutageSeconds: componentID == ClaudeStatusComponentCatalog.claudeCodeID && index == 32 ? 900 : 0,
                    majorOutageSeconds: 0,
                    relatedEvents: [],
                    barFillHex: nil
                )
            },
            sourceUptimePercent: nil
        )
    }

    private func openAIHistory(groupID: String, groupName: String) -> OpenAIStatusUptimeHistory {
        OpenAIStatusUptimeHistory(
            groupID: groupID,
            groupName: groupName,
            startDate: nil,
            days: (0..<45).map { index in
                OpenAIStatusUptimeDay(
                    date: date(offset: index),
                    degradedPerformanceSeconds: groupID == OpenAIStatusGroupCatalog.codexID && index == 32 ? 900 : 0,
                    partialOutageSeconds: 0,
                    fullOutageSeconds: 0,
                    relatedEvents: []
                )
            },
            sourceUptimePercent: nil
        )
    }

    private func date(offset: Int) -> Date {
        baseDate.addingTimeInterval(TimeInterval(offset * 86_400))
    }
}
