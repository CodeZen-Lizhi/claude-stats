import Foundation
import Testing
@testable import ClaudeStats

@Suite("OpenAIStatusClient")
struct OpenAIStatusClientTests {
    @Test("Decodes components and aggregates product groups")
    func decodesComponentsAndGroups() throws {
        let snapshot = try OpenAIStatusClient.decodeStatus(
            summaryData: Self.operationalSummary,
            componentsData: Self.componentsData(),
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.pageName == "OpenAI")
        #expect(snapshot.rollup.severity == .operational)
        #expect(snapshot.components.count == 30)
        #expect(snapshot.groups.map(\.name) == ["APIs", "ChatGPT", "Codex", "FedRAMP"])
        #expect(snapshot.groups.first { $0.id == OpenAIStatusGroupCatalog.chatGPTID }?.status == .operational)
        #expect(snapshot.groups.first { $0.id == OpenAIStatusGroupCatalog.codexID }?.status == .operational)
        #expect(snapshot.fetchedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("Worst child component status drives group status")
    func groupStatusUsesWorstChild() throws {
        let snapshot = try OpenAIStatusClient.decodeStatus(
            summaryData: Self.abnormalSummary,
            componentsData: Self.componentsData(statusOverrides: [
                OpenAIStatusGroupCatalog.chatGPTLoginID: "full_outage",
                OpenAIStatusGroupCatalog.codexAPIID: "degraded_performance",
            ]),
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(snapshot.rollup.severity == .partialOutage)
        #expect(snapshot.groups.first { $0.id == OpenAIStatusGroupCatalog.chatGPTID }?.status == .fullOutage)
        #expect(snapshot.groups.first { $0.id == OpenAIStatusGroupCatalog.codexID }?.status == .degradedPerformance)
        #expect(snapshot.activeIncident?.name == "Elevated errors")
        #expect(snapshot.activeIncident?.impact == .partialOutage)
        #expect(snapshot.scheduledMaintenances.first?.impact == .underMaintenance)
    }

    @Test("Unknown component status is preserved")
    func unknownStatus() throws {
        let snapshot = try OpenAIStatusClient.decodeStatus(
            summaryData: Self.operationalSummary,
            componentsData: Self.componentsData(statusOverrides: [
                OpenAIStatusGroupCatalog.responsesID: "new_status",
            ])
        )

        #expect(snapshot.components.first { $0.id == OpenAIStatusGroupCatalog.responsesID }?.status == .unknown("new_status"))
        #expect(snapshot.groups.first { $0.id == OpenAIStatusGroupCatalog.apisID }?.status == .unknown("new_status"))
    }

    @Test("Decodes current summary shape without incident arrays")
    func decodesSummaryWithoutIncidentArrays() throws {
        let snapshot = try OpenAIStatusClient.decodeStatus(
            summaryData: Self.summaryWithoutIncidentArrays,
            componentsData: Self.componentsData()
        )

        #expect(snapshot.pageName == "OpenAI")
        #expect(snapshot.rollup.description == "All Systems Operational")
        #expect(snapshot.incidents.isEmpty)
        #expect(snapshot.scheduledMaintenances.isEmpty)
        #expect(snapshot.components.count == 30)
    }

    private static func componentsData(statusOverrides: [String: String] = [:]) -> Data {
        let components = Self.components.enumerated().map { offset, component in
            let status = statusOverrides[component.id] ?? "operational"
            return """
            {"id":"\(component.id)","name":"\(component.name)","status":"\(status)","updated_at":"2026-05-16T18:24:42Z","position":\(offset)}
            """
        }
        .joined(separator: ",")
        return Data(#"{"components":[\#(components)]}"#.utf8)
    }

    private static let components: [(id: String, name: String)] = [
        (OpenAIStatusGroupCatalog.responsesID, "Responses"),
        (OpenAIStatusGroupCatalog.fineTuningID, "Fine-tuning"),
        (OpenAIStatusGroupCatalog.imagesID, "Images"),
        (OpenAIStatusGroupCatalog.batchID, "Batch"),
        (OpenAIStatusGroupCatalog.moderationsID, "Moderations"),
        (OpenAIStatusGroupCatalog.embeddingsID, "Embeddings"),
        (OpenAIStatusGroupCatalog.filesID, "Files"),
        (OpenAIStatusGroupCatalog.apiLoginID, "Login"),
        (OpenAIStatusGroupCatalog.fileUploadsID, "File uploads"),
        (OpenAIStatusGroupCatalog.codexCLIID, "CLI"),
        (OpenAIStatusGroupCatalog.fedRAMPComponentID, "FedRAMP"),
        (OpenAIStatusGroupCatalog.complianceAPIID, "Compliance API"),
        (OpenAIStatusGroupCatalog.chatGPTAtlasID, "ChatGPT Atlas"),
        (OpenAIStatusGroupCatalog.realtimeID, "Realtime"),
        (OpenAIStatusGroupCatalog.soraID, "Sora"),
        (OpenAIStatusGroupCatalog.conversationsID, "Conversations"),
        (OpenAIStatusGroupCatalog.agentID, "Agent"),
        (OpenAIStatusGroupCatalog.connectorsAppsID, "Connectors/Apps"),
        (OpenAIStatusGroupCatalog.codexAPIID, "Codex API"),
        (OpenAIStatusGroupCatalog.deepResearchID, "Deep Research"),
        (OpenAIStatusGroupCatalog.searchID, "Search"),
        (OpenAIStatusGroupCatalog.gptsID, "GPTs"),
        (OpenAIStatusGroupCatalog.imageGenerationID, "Image Generation"),
        (OpenAIStatusGroupCatalog.audioID, "Audio"),
        (OpenAIStatusGroupCatalog.codexVSCodeExtensionID, "VS Code extension"),
        (OpenAIStatusGroupCatalog.voiceModeID, "Voice mode"),
        (OpenAIStatusGroupCatalog.chatCompletionsID, "Chat Completions"),
        (OpenAIStatusGroupCatalog.chatGPTLoginID, "Login"),
        (OpenAIStatusGroupCatalog.codexWebID, "Codex Web"),
        (OpenAIStatusGroupCatalog.codexAppID, "App"),
    ]

    private static let operationalSummary = Data("""
    {
      "page": {"id": "01JMDK9XYNY6RXSED6SDWW50WY", "name": "OpenAI", "updated_at": "2026-05-16T18:24:42.297Z"},
      "incidents": [],
      "scheduled_maintenances": [],
      "status": {"indicator": "none", "description": "All Systems Operational"}
    }
    """.utf8)

    private static let summaryWithoutIncidentArrays = Data("""
    {
      "page": {"id": "01JMDK9XYNY6RXSED6SDWW50WY", "name": "OpenAI", "updated_at": "2026-04-27T15:52:49Z"},
      "components": [],
      "status": {"indicator": "none", "description": "All Systems Operational"}
    }
    """.utf8)

    private static let abnormalSummary = Data("""
    {
      "page": {"id": "01JMDK9XYNY6RXSED6SDWW50WY", "name": "OpenAI", "updated_at": "2026-05-16T18:24:42Z"},
      "incidents": [
        {"id": "incident-1", "name": "Elevated errors", "status": "investigating", "impact": "major", "shortlink": "https://stspg.io/test", "started_at": "2026-05-16T18:00:00Z", "updated_at": "2026-05-16T18:10:00Z"}
      ],
      "scheduled_maintenances": [
        {"id": "maint-1", "name": "Planned work", "status": "scheduled", "impact": "maintenance", "shortlink": "https://stspg.io/maint", "scheduled_for": "2026-05-17T01:00:00Z", "scheduled_until": "2026-05-17T02:00:00Z", "updated_at": "2026-05-16T18:12:00Z"}
      ],
      "status": {"indicator": "major", "description": "Partial System Outage"}
    }
    """.utf8)
}
