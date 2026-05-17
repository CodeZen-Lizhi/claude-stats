import Foundation

enum OpenAIStatusUptimeHTMLParser {
    enum ParserError: Error, Sendable, Equatable {
        case missingStatusData(String)
        case malformedStatusData(String)
        case decoding(String)
    }

    static func parse(_ html: String, fetchedAt: Date = .now) throws -> OpenAIStatusUptimeSnapshot {
        let normalized = normalize(html)
        let liveDefinitions = extractGroupDefinitions(from: normalized)
        let groupDefinitions = liveDefinitions.isEmpty
            ? OpenAIStatusGroupCatalog.defaultGroupDefinitions
            : liveDefinitions

        let impacts: [ComponentImpact] = try decodeArray(named: "component_impacts", from: normalized)
        let uptimes: [ComponentUptime] = try decodeArray(named: "component_uptimes", from: normalized)
        let incidentLinks: [IncidentLink] = (try? decodeArray(named: "incident_links", from: normalized)) ?? []
        let incidentLinksByID = Dictionary(uniqueKeysWithValues: incidentLinks.map { ($0.id, $0) })
        let uptimesByComponentID = Dictionary(grouping: uptimes.filter { !$0.componentID.isUndefinedValue }, by: \.componentID)
        let uptimesByGroupID = Dictionary(uniqueKeysWithValues: uptimes
            .filter { !$0.statusPageComponentGroupID.isUndefinedValue }
            .map { ($0.statusPageComponentGroupID, $0) })

        let histories = Dictionary(uniqueKeysWithValues: groupDefinitions.map { definition in
            let groupImpacts = impacts.filter { definition.componentIDs.contains($0.componentID) }
            let groupUptime = uptimesByGroupID[definition.id]
            let sourceStart = groupUptime?.dataAvailableSinceDate
                ?? definition.componentIDs
                    .flatMap { uptimesByComponentID[$0] ?? [] }
                    .compactMap(\.dataAvailableSinceDate)
                    .min()
            let history = history(
                for: definition,
                impacts: groupImpacts,
                incidentLinksByID: incidentLinksByID,
                startDate: sourceStart.map(dayStart),
                sourceUptimePercent: groupUptime?.uptimePercent,
                fetchedAt: fetchedAt
            )
            return (definition.id, history)
        })

        return OpenAIStatusUptimeSnapshot(
            histories: histories,
            groupDefinitions: groupDefinitions,
            fetchedAt: fetchedAt
        )
    }

    private static func history(
        for definition: OpenAIStatusGroupDefinition,
        impacts: [ComponentImpact],
        incidentLinksByID: [String: IncidentLink],
        startDate: Date?,
        sourceUptimePercent: Double?,
        fetchedAt: Date
    ) -> OpenAIStatusUptimeHistory {
        OpenAIStatusUptimeHistory(
            groupID: definition.id,
            groupName: definition.name,
            startDate: startDate,
            days: windowDates(endingAt: fetchedAt).map { date in
                day(date, impacts: impacts, incidentLinksByID: incidentLinksByID, fetchedAt: fetchedAt)
            },
            sourceUptimePercent: sourceUptimePercent
        )
    }

    private static func day(
        _ date: Date,
        impacts: [ComponentImpact],
        incidentLinksByID: [String: IncidentLink],
        fetchedAt: Date
    ) -> OpenAIStatusUptimeDay {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(TimeInterval(OpenAIStatusUptimeWindow.secondsPerDay))
        var degradedSeconds = 0
        var partialSeconds = 0
        var fullSeconds = 0
        var eventIDs: [String] = []

        for impact in impacts {
            guard let start = impact.startAtDate else { continue }
            let end = impact.endAtDate ?? fetchedAt
            guard end > date, start < dayEnd else { continue }

            let overlapStart = max(start, date)
            let overlapEnd = min(end, dayEnd)
            let seconds = max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded()))
            guard seconds > 0 else { continue }

            switch OpenAIStatusSeverity(componentStatus: impact.status) {
            case .fullOutage:
                fullSeconds += seconds
            case .partialOutage:
                partialSeconds += seconds
            case .degradedPerformance:
                degradedSeconds += seconds
            case .operational, .underMaintenance, .unknown:
                break
            }
            if !eventIDs.contains(impact.statusPageIncidentID) {
                eventIDs.append(impact.statusPageIncidentID)
            }
        }

        let events = eventIDs.map { id in
            if let incident = incidentLinksByID[id] {
                return OpenAIStatusUptimeEvent(name: incident.name, code: id, permalink: incident.permalink)
            }
            return OpenAIStatusUptimeEvent(name: "Incident \(id)", code: id, permalink: nil)
        }

        return OpenAIStatusUptimeDay(
            date: date,
            degradedPerformanceSeconds: min(OpenAIStatusUptimeWindow.secondsPerDay, degradedSeconds),
            partialOutageSeconds: min(OpenAIStatusUptimeWindow.secondsPerDay, partialSeconds),
            fullOutageSeconds: min(OpenAIStatusUptimeWindow.secondsPerDay, fullSeconds),
            relatedEvents: events
        )
    }

    private static func extractGroupDefinitions(from text: String) -> [OpenAIStatusGroupDefinition] {
        var definitions: [OpenAIStatusGroupDefinition] = []
        var seen: Set<String> = []
        var searchStart = text.startIndex

        while let keyRange = text.range(of: #""group":"#, range: searchStart..<text.endIndex),
              let objectStart = text[keyRange.upperBound...].firstIndex(of: "{"),
              let objectEnd = balancedEnd(startingAt: objectStart, opening: "{", closing: "}", in: text) {
            let object = String(text[objectStart...objectEnd])
            if let data = object.data(using: .utf8),
               let payload = try? JSONDecoder().decode(GroupPayload.self, from: data),
               !seen.contains(payload.id) {
                seen.insert(payload.id)
                definitions.append(payload.definition(position: definitions.count + 1))
            }
            searchStart = text.index(after: objectEnd)
        }

        return definitions
    }

    private static func decodeArray<T: Decodable>(named name: String, from text: String) throws -> [T] {
        let json = try extractArrayJSON(named: name, from: text)
        guard let data = json.data(using: .utf8) else {
            throw ParserError.malformedStatusData(name)
        }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            throw ParserError.decoding(String(describing: error))
        }
    }

    private static func extractArrayJSON(named name: String, from text: String) throws -> String {
        let marker = #""\#(name)":["#
        guard let markerRange = text.range(of: marker) else {
            throw ParserError.missingStatusData(name)
        }
        guard let arrayStart = text[markerRange.lowerBound...].firstIndex(of: "["),
              let arrayEnd = balancedEnd(startingAt: arrayStart, opening: "[", closing: "]", in: text) else {
            throw ParserError.malformedStatusData(name)
        }
        return String(text[arrayStart...arrayEnd])
    }

    private static func balancedEnd(
        startingAt start: String.Index,
        opening: Character,
        closing: Character,
        in text: String
    ) -> String.Index? {
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func normalize(_ html: String) -> String {
        html
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003c", with: "<")
            .replacingOccurrences(of: "\\u003e", with: ">")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private static func windowDates(endingAt fetchedAt: Date) -> [Date] {
        let today = dayStart(fetchedAt)
        let first = calendar.date(
            byAdding: .day,
            value: -(OpenAIStatusUptimeWindow.dayCount - 1),
            to: today
        ) ?? today
        return (0..<OpenAIStatusUptimeWindow.dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first)
        }
    }

    private static func dayStart(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isUndefinedValue else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private struct GroupPayload: Decodable {
        let id: String
        let name: String
        let components: [Component]
        let hidden: Bool?

        func definition(position: Int) -> OpenAIStatusGroupDefinition {
            OpenAIStatusGroupDefinition(
                id: id,
                name: name,
                componentIDs: components
                    .filter { $0.hidden != true }
                    .map(\.componentID)
                    .filter { !$0.isUndefinedValue },
                position: position
            )
        }

        struct Component: Decodable {
            let componentID: String
            let hidden: Bool?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case hidden
            }
        }
    }

    private struct ComponentImpact: Decodable {
        let componentID: String
        let endAt: String?
        let id: String
        let startAt: String
        let status: String
        let statusPageIncidentID: String

        var startAtDate: Date? { OpenAIStatusUptimeHTMLParser.parseDate(startAt) }
        var endAtDate: Date? { OpenAIStatusUptimeHTMLParser.parseDate(endAt) }

        enum CodingKeys: String, CodingKey {
            case componentID = "component_id"
            case endAt = "end_at"
            case id
            case startAt = "start_at"
            case status
            case statusPageIncidentID = "status_page_incident_id"
        }
    }

    private struct ComponentUptime: Decodable {
        let componentID: String
        let dataAvailableSince: String?
        let statusPageComponentGroupID: String
        let uptime: String

        var dataAvailableSinceDate: Date? { OpenAIStatusUptimeHTMLParser.parseDate(dataAvailableSince) }
        var uptimePercent: Double? { Double(uptime) }

        enum CodingKeys: String, CodingKey {
            case componentID = "component_id"
            case dataAvailableSince = "data_available_since"
            case statusPageComponentGroupID = "status_page_component_group_id"
            case uptime
        }
    }

    private struct IncidentLink: Decodable {
        let id: String
        let name: String
        let permalink: URL?
    }
}

private extension String {
    var isUndefinedValue: Bool {
        self == "$undefined" || self == "__undefined__"
    }
}
