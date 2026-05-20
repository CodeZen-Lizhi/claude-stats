import Foundation

enum OpenAIStatusSeverity: Sendable, Codable, Equatable, Comparable {
    case operational
    case degradedPerformance
    case partialOutage
    case fullOutage
    case underMaintenance
    case unknown(String)

    init(componentStatus rawValue: String) {
        switch rawValue {
        case "operational": self = .operational
        case "degraded_performance": self = .degradedPerformance
        case "partial_outage": self = .partialOutage
        case "full_outage", "major_outage": self = .fullOutage
        case "under_maintenance": self = .underMaintenance
        default: self = .unknown(rawValue)
        }
    }

    init(indicator rawValue: String) {
        switch rawValue {
        case "none": self = .operational
        case "minor": self = .degradedPerformance
        case "major": self = .partialOutage
        case "critical": self = .fullOutage
        case "maintenance": self = .underMaintenance
        default: self = .unknown(rawValue)
        }
    }

    var isOperational: Bool {
        self == .operational
    }

    var rawStatus: String {
        switch self {
        case .operational: "operational"
        case .degradedPerformance: "degraded_performance"
        case .partialOutage: "partial_outage"
        case .fullOutage: "full_outage"
        case .underMaintenance: "under_maintenance"
        case .unknown(let raw): raw
        }
    }

    var displayName: String {
        switch self {
        case .operational:
            L10n.string("status.severity.operational", defaultValue: "Operational")
        case .degradedPerformance:
            L10n.string("status.severity.degraded_performance", defaultValue: "Degraded Performance")
        case .partialOutage:
            L10n.string("status.severity.partial_outage", defaultValue: "Partial Outage")
        case .fullOutage:
            L10n.string("status.severity.full_outage", defaultValue: "Full Outage")
        case .underMaintenance:
            L10n.string("status.severity.under_maintenance", defaultValue: "Under Maintenance")
        case .unknown:
            L10n.string("status.severity.unknown", defaultValue: "Unknown")
        }
    }

    private var rank: Int {
        switch self {
        case .operational: 0
        case .underMaintenance: 1
        case .degradedPerformance: 2
        case .partialOutage: 3
        case .fullOutage: 4
        case .unknown: 5
        }
    }

    static func < (lhs: OpenAIStatusSeverity, rhs: OpenAIStatusSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(componentStatus: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawStatus)
    }
}

struct OpenAIStatusRollup: Sendable, Codable, Equatable {
    let severity: OpenAIStatusSeverity
    let description: String
}

struct OpenAIStatusComponent: Identifiable, Sendable, Codable, Equatable {
    let id: String
    let name: String
    let status: OpenAIStatusSeverity
    let updatedAt: Date?
    let position: Int

    var isOperational: Bool { status.isOperational }
}

struct OpenAIStatusGroupDefinition: Identifiable, Sendable, Codable, Equatable {
    let id: String
    let name: String
    let componentIDs: [String]
    let position: Int
}

struct OpenAIStatusGroup: Identifiable, Sendable, Codable, Equatable {
    let id: String
    let name: String
    let status: OpenAIStatusSeverity
    let updatedAt: Date?
    let position: Int
    let componentIDs: [String]

    var isOperational: Bool { status.isOperational }
}

struct OpenAIStatusIncident: Identifiable, Sendable, Codable, Equatable {
    let id: String
    let name: String
    let status: String
    let impact: OpenAIStatusSeverity
    let shortlink: URL?
    let startedAt: Date?
    let updatedAt: Date?

    var isResolved: Bool {
        status == "resolved" || status == "completed"
    }
}

struct OpenAIStatusMaintenance: Identifiable, Sendable, Codable, Equatable {
    let id: String
    let name: String
    let status: String
    let impact: OpenAIStatusSeverity
    let shortlink: URL?
    let scheduledFor: Date?
    let scheduledUntil: Date?
    let updatedAt: Date?

    var isActive: Bool {
        status == "in_progress"
    }
}

struct OpenAIStatusSnapshot: Sendable, Codable, Equatable {
    let pageName: String
    let pageUpdatedAt: Date?
    let rollup: OpenAIStatusRollup
    let groups: [OpenAIStatusGroup]
    let components: [OpenAIStatusComponent]
    let incidents: [OpenAIStatusIncident]
    let scheduledMaintenances: [OpenAIStatusMaintenance]
    let fetchedAt: Date

    var worstVisibleSeverity: OpenAIStatusSeverity {
        groups.map(\.status).max() ?? rollup.severity
    }

    var activeIncident: OpenAIStatusIncident? {
        incidents.first { !$0.isResolved }
    }
}

enum OpenAIStatusGroupCatalog {
    static let apisID = "01K5H8S53SY1KMS4GQMNMQM1K5"
    static let chatGPTID = "01K5H8S53SY1KMS4GQMNMZXTR1"
    static let codexID = "01KMKF9EBTCD8BN9PG8DJZXRSQ"
    static let fedRAMPID = "01KKACDSZF5G5JTBJY83GF176Z"

    static let chatCompletionsID = "01JMXBRMFE6N2NNT7DG6XZQ6PW"
    static let responsesID = "01JP8CD9JR3HR6Y7G4Q75N4DVW"
    static let fineTuningID = "01JMXBRMFEMZK0HPK19RYET250"
    static let embeddingsID = "01JMXBRMFEV0AJ0VVS68N9CD6R"
    static let imagesID = "01JMXBRMFE4MAP2BHSJNZ787WX"
    static let batchID = "01JMXBRMFE5ESNNV8JDHVCGSRD"
    static let audioID = "01JMXBRMFEKVBWKK82B44QFMCE"
    static let moderationsID = "01JMXBRMFEVZ7E0X9GD9FWR9WX"
    static let realtimeID = "01JMXBRMFEQW613TFE89F45035"
    static let filesID = "01JMXBRMFESJCBGJR10PDD3WCQ"
    static let apiLoginID = "01JSM5RTJWHRWDTS6Q604VEW3B"
    static let soraID = "01K9G527YRPY1EFRMHTKB5BKT5"

    static let conversationsID = "01JMXBNJXGV1T5GT2M9XA83XNG"
    static let chatGPTLoginID = "01JMXBNJXG1S2D9V65P1ZZTD94"
    static let complianceAPIID = "01JNKS9D9S72PMP1938PVFFQN4"
    static let searchID = "01JMXBNJXGKKP51D4DEJ2HZJ8Q"
    static let fileUploadsID = "01JMXBNJXG1YMQPPCPCQX3MPA2"
    static let voiceModeID = "01JMXBNJXGGT5SR5DB9J7GYY48"
    static let gptsID = "01JSFK5QX36ZRW0TW0ZV0ZYFXQ"
    static let imageGenerationID = "01JQ7EKW990MSPSWVXC7VPV2ZJ"
    static let deepResearchID = "01JSYVYQSWMJ9QG35XHP08BHA7"
    static let agentID = "01JSG1XMJ9RVJJQ0E85NVSJ2AZ"
    static let chatGPTAtlasID = "01K8C008QVXHA6JX98PAS42VPD"
    static let connectorsAppsID = "01K6TVGGGDCP0PPGCHXAG3AQX8"

    static let codexWebID = "01JVCV8YSWZFRSM1G5CVP253SK"
    static let codexAppID = "01KMKFAMWKQ81YWSE1Z18R6VHR"
    static let codexAPIID = "01KMP3KP5MGE23B80K1EK4S8PV"
    static let codexCLIID = "01KMKFAMWKNQ84Z1766MV08ZDE"
    static let codexVSCodeExtensionID = "01KMP3KP5M8X0EBTVW6KN327EE"

    static let fedRAMPComponentID = "01KKAD7C71MCCH3FTREMJH4AAS"

    static let defaultVisibleGroupIDs: Set<String> = [chatGPTID, codexID]
    static let defaultVisibleGroupNames: Set<String> = ["ChatGPT", "Codex"]

    static let defaultGroupDefinitions: [OpenAIStatusGroupDefinition] = [
        OpenAIStatusGroupDefinition(
            id: apisID,
            name: "APIs",
            componentIDs: [
                chatCompletionsID, responsesID, fineTuningID, embeddingsID,
                imagesID, batchID, audioID, moderationsID, realtimeID, filesID,
                apiLoginID, soraID,
            ],
            position: 1
        ),
        OpenAIStatusGroupDefinition(
            id: chatGPTID,
            name: "ChatGPT",
            componentIDs: [
                conversationsID, chatGPTLoginID, complianceAPIID, searchID,
                fileUploadsID, voiceModeID, gptsID, imageGenerationID,
                deepResearchID, agentID, chatGPTAtlasID, connectorsAppsID,
            ],
            position: 2
        ),
        OpenAIStatusGroupDefinition(
            id: codexID,
            name: "Codex",
            componentIDs: [codexWebID, codexAppID, codexAPIID, codexCLIID, codexVSCodeExtensionID],
            position: 3
        ),
        OpenAIStatusGroupDefinition(
            id: fedRAMPID,
            name: "FedRAMP",
            componentIDs: [fedRAMPComponentID],
            position: 4
        ),
    ]

    static let fallbackGroups: [OpenAIStatusGroup] = groups(from: [])

    static func groups(
        from components: [OpenAIStatusComponent],
        definitions: [OpenAIStatusGroupDefinition] = defaultGroupDefinitions
    ) -> [OpenAIStatusGroup] {
        let componentsByID = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0) })
        return definitions.map { definition in
            let groupComponents = definition.componentIDs.compactMap { componentsByID[$0] }
            return OpenAIStatusGroup(
                id: definition.id,
                name: definition.name,
                status: groupComponents.map(\.status).max() ?? .unknown("unknown"),
                updatedAt: groupComponents.compactMap(\.updatedAt).max(),
                position: definition.position,
                componentIDs: definition.componentIDs
            )
        }
        .sorted { lhs, rhs in
            if lhs.position == rhs.position { return lhs.name < rhs.name }
            return lhs.position < rhs.position
        }
    }

    static func visibleGroupIDs(from storedIDs: Set<String>, groups: [OpenAIStatusGroup]) -> Set<String> {
        guard !groups.isEmpty else { return storedIDs.isEmpty ? defaultVisibleGroupIDs : storedIDs }

        let ids = Set(groups.map(\.id))
        var visible = storedIDs.intersection(ids)

        let fallbackByID = Dictionary(uniqueKeysWithValues: fallbackGroups.map { ($0.id, $0.name) })
        for missingID in storedIDs.subtracting(ids) {
            guard let name = fallbackByID[missingID],
                  let current = groups.first(where: { $0.name == name }) else {
                continue
            }
            visible.insert(current.id)
        }

        if visible.isEmpty {
            visible = Set(groups.filter { defaultVisibleGroupNames.contains($0.name) }.map(\.id))
        }
        if visible.isEmpty {
            visible = defaultVisibleGroupIDs.intersection(ids)
        }
        if visible.isEmpty, let first = groups.sorted(by: { $0.position < $1.position }).first {
            visible.insert(first.id)
        }
        return visible
    }

    static func visibleGroups(from groups: [OpenAIStatusGroup], storedIDs: Set<String>) -> [OpenAIStatusGroup] {
        let effectiveIDs = visibleGroupIDs(from: storedIDs, groups: groups)
        return groups
            .filter { effectiveIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.position == rhs.position { return lhs.name < rhs.name }
                return lhs.position < rhs.position
            }
    }

    static func equivalentIDs(for group: OpenAIStatusGroup) -> Set<String> {
        let known = fallbackGroups.filter { $0.name == group.name }.map(\.id)
        return Set(known + [group.id])
    }
}
