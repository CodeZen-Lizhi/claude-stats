import Foundation

/// Decoded shape of the GraphQL `viewer.contributionsCollection.contributionCalendar`
/// query we send. Only the fields the dashboard renders are listed.
struct GitHubContributionsResponse: Sendable, Decodable {
    let data: DataNode?
    let errors: [ErrorNode]?

    struct DataNode: Sendable, Decodable {
        let viewer: Viewer
    }
    struct Viewer: Sendable, Decodable {
        let login: String
        let contributionsCollection: Collection
    }
    struct Collection: Sendable, Decodable {
        let contributionCalendar: Cal
    }
    struct Cal: Sendable, Decodable {
        let totalContributions: Int
        let weeks: [Week]
    }
    struct Week: Sendable, Decodable {
        let contributionDays: [Day]
    }
    struct Day: Sendable, Decodable {
        let date: String              // "2026-05-14" in the viewer's GitHub TZ
        let contributionCount: Int
    }
    struct ErrorNode: Sendable, Decodable {
        let message: String
        let type: String?
    }
}

/// Stateless GitHub GraphQL client. Holds no credentials in memory — callers
/// pass the PAT per call, so a token change doesn't require recreating the
/// client.
///
/// Returns a `CalendarSnapshot` of per-local-day contribution counts already
/// shaped as `HeatmapCell`s so the dashboard can join against the local
/// heatmap on `Date` keys without an intermediate type.
struct GitHubClient: Sendable {
    enum ClientError: Error, Sendable, CustomStringConvertible {
        case unauthorized
        case rateLimited(retryAfter: Date?)
        case graphQL([String])
        case http(status: Int)
        case network(URLError)
        case decoding(String)

        var description: String {
            switch self {
            case .unauthorized: return "Token rejected. Re-enter your PAT in Settings."
            case .rateLimited(let retry):
                if let retry { return "GitHub rate limit hit. Try again \(Format.relativeDate(retry))." }
                return "GitHub rate limit hit. Try again later."
            case .graphQL(let messages):
                return messages.first ?? "GitHub returned an unspecified GraphQL error."
            case .http(let status): return "GitHub returned HTTP \(status)."
            case .network: return "Offline or unreachable."
            case .decoding: return "Unexpected response shape from GitHub."
            }
        }
    }

    struct CalendarSnapshot: Sendable, Codable {
        let login: String
        let totalContributions: Int
        let cells: [HeatmapCell]
        let fetchedAt: Date
    }

    private static let endpoint = URL(string: "https://api.github.com/graphql")!
    private static let queryString = """
    query($from: DateTime!, $to: DateTime!) {
      viewer {
        login
        contributionsCollection(from: $from, to: $to) {
          contributionCalendar {
            totalContributions
            weeks {
              contributionDays {
                date
                contributionCount
              }
            }
          }
        }
      }
    }
    """

    func fetchCalendar(token: String, from: Date, to: Date, now: Date = .now) async throws -> CalendarSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let body: [String: Any] = [
            "query": Self.queryString,
            "variables": ["from": iso.string(from: from), "to": iso.string(from: to)],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw ClientError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(status: -1)
        }
        Log.network.notice("GitHub fetchCalendar \(http.statusCode, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000))ms")

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ClientError.unauthorized
        case 403, 429:
            let retryAfter = Self.retryAfter(http: http, now: now)
            throw ClientError.rateLimited(retryAfter: retryAfter)
        default:
            throw ClientError.http(status: http.statusCode)
        }

        let decoded: GitHubContributionsResponse
        do {
            decoded = try JSONDecoder().decode(GitHubContributionsResponse.self, from: data)
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
        if let errors = decoded.errors, !errors.isEmpty {
            throw ClientError.graphQL(errors.map(\.message))
        }
        guard let viewer = decoded.data?.viewer else {
            throw ClientError.decoding("missing viewer")
        }
        let cells = Self.cells(from: viewer.contributionsCollection.contributionCalendar)
        return CalendarSnapshot(
            login: viewer.login,
            totalContributions: viewer.contributionsCollection.contributionCalendar.totalContributions,
            cells: cells,
            fetchedAt: now
        )
    }

    // MARK: - Helpers

    private static let userAgent: String = {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        return "ClaudeStats/\(v)"
    }()

    /// GitHub's date strings are `YYYY-MM-DD` in the viewer's GitHub TZ. We
    /// parse them in the device's local calendar so the resulting `Date` is
    /// the start-of-local-day — that matches `DashboardActivityBuilder`'s
    /// bucketing and lets the overlap join on `Date` keys without TZ drift.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func cells(from calendar: GitHubContributionsResponse.Cal) -> [HeatmapCell] {
        var out: [HeatmapCell] = []
        for week in calendar.weeks {
            for day in week.contributionDays {
                guard let parsed = dayParser.date(from: day.date) else { continue }
                let dayStart = Calendar.current.startOfDay(for: parsed)
                out.append(HeatmapCell(date: dayStart, value: day.contributionCount))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private static func retryAfter(http: HTTPURLResponse, now: Date) -> Date? {
        if let resetHeader = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetSeconds = TimeInterval(resetHeader) {
            return Date(timeIntervalSince1970: resetSeconds)
        }
        if let retryHeader = http.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryHeader) {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }
}

