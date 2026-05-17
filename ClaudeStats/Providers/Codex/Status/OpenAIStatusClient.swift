import Foundation

protocol OpenAIStatusFetching: Sendable {
    func fetchSummary(now: Date) async throws -> OpenAIStatusSnapshot
}

struct OpenAIStatusClient: OpenAIStatusFetching {
    enum ClientError: Error, Sendable, CustomStringConvertible, Equatable {
        case http(status: Int)
        case network(String)
        case decoding(String)

        var description: String {
            switch self {
            case .http(let status): "OpenAI Status returned HTTP \(status)."
            case .network: "OpenAI Status is unreachable."
            case .decoding: "OpenAI Status returned an unexpected response."
            }
        }
    }

    private let summaryEndpoint: URL
    private let componentsEndpoint: URL

    init(
        summaryEndpoint: URL = URL(string: "https://status.openai.com/api/v2/summary.json")!,
        componentsEndpoint: URL = URL(string: "https://status.openai.com/api/v2/components.json")!
    ) {
        self.summaryEndpoint = summaryEndpoint
        self.componentsEndpoint = componentsEndpoint
    }

    func fetchSummary(now: Date = .now) async throws -> OpenAIStatusSnapshot {
        async let summary = fetch(endpoint: summaryEndpoint, label: "summary")
        async let components = fetch(endpoint: componentsEndpoint, label: "components")
        let (summaryData, componentsData) = try await (summary, components)
        return try Self.decodeStatus(
            summaryData: summaryData,
            componentsData: componentsData,
            now: now
        )
    }

    private func fetch(endpoint: URL, label: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw ClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(status: -1)
        }
        Log.network.notice("OpenAI Status \(label, privacy: .public) fetch \(http.statusCode, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000))ms")

        guard (200...299).contains(http.statusCode) else {
            throw ClientError.http(status: http.statusCode)
        }
        return data
    }

    static func decodeStatus(summaryData: Data, componentsData: Data, now: Date = .now) throws -> OpenAIStatusSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        do {
            let summary = try decoder.decode(OpenAIStatusSummaryResponse.self, from: summaryData)
            let componentsResponse = try decoder.decode(OpenAIStatusComponentsResponse.self, from: componentsData)
            return summary.snapshot(
                components: componentsResponse.components.map(\.model),
                fetchedAt: now
            )
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) {
            return date
        }
        throw ClientError.decoding("invalid date: \(raw)")
    }

    static let userAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        return "ClaudeStats/\(version)"
    }()
}

private struct OpenAIStatusSummaryResponse: Decodable {
    let page: Page
    let incidents: [Incident]?
    let scheduledMaintenances: [Maintenance]?
    let status: Status

    enum CodingKeys: String, CodingKey {
        case page
        case incidents
        case scheduledMaintenances = "scheduled_maintenances"
        case status
    }

    func snapshot(components: [OpenAIStatusComponent], fetchedAt: Date) -> OpenAIStatusSnapshot {
        let sortedComponents = components.sorted { lhs, rhs in
            if lhs.position == rhs.position { return lhs.name < rhs.name }
            return lhs.position < rhs.position
        }
        return OpenAIStatusSnapshot(
            pageName: page.name,
            pageUpdatedAt: page.updatedAt,
            rollup: OpenAIStatusRollup(
                severity: OpenAIStatusSeverity(indicator: status.indicator),
                description: status.description
            ),
            groups: OpenAIStatusGroupCatalog.groups(from: sortedComponents),
            components: sortedComponents,
            incidents: (incidents ?? []).map(\.model),
            scheduledMaintenances: (scheduledMaintenances ?? []).map(\.model),
            fetchedAt: fetchedAt
        )
    }

    struct Page: Decodable {
        let name: String
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case name
            case updatedAt = "updated_at"
        }
    }

    struct Status: Decodable {
        let indicator: String
        let description: String
    }

    struct Incident: Decodable {
        let id: String
        let name: String
        let status: String
        let impact: String?
        let shortlink: URL?
        let startedAt: Date?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case status
            case impact
            case shortlink
            case startedAt = "started_at"
            case updatedAt = "updated_at"
        }

        var model: OpenAIStatusIncident {
            OpenAIStatusIncident(
                id: id,
                name: name,
                status: status,
                impact: OpenAIStatusSeverity(indicator: impact ?? "none"),
                shortlink: shortlink,
                startedAt: startedAt,
                updatedAt: updatedAt
            )
        }
    }

    struct Maintenance: Decodable {
        let id: String
        let name: String
        let status: String
        let impact: String?
        let shortlink: URL?
        let scheduledFor: Date?
        let scheduledUntil: Date?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case status
            case impact
            case shortlink
            case scheduledFor = "scheduled_for"
            case scheduledUntil = "scheduled_until"
            case updatedAt = "updated_at"
        }

        var model: OpenAIStatusMaintenance {
            OpenAIStatusMaintenance(
                id: id,
                name: name,
                status: status,
                impact: OpenAIStatusSeverity(indicator: impact ?? "none"),
                shortlink: shortlink,
                scheduledFor: scheduledFor,
                scheduledUntil: scheduledUntil,
                updatedAt: updatedAt
            )
        }
    }
}

private struct OpenAIStatusComponentsResponse: Decodable {
    let components: [Component]

    struct Component: Decodable {
        let id: String
        let name: String
        let status: String
        let updatedAt: Date?
        let position: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case status
            case updatedAt = "updated_at"
            case position
        }

        var model: OpenAIStatusComponent {
            OpenAIStatusComponent(
                id: id,
                name: name,
                status: OpenAIStatusSeverity(componentStatus: status),
                updatedAt: updatedAt,
                position: position
            )
        }
    }
}
