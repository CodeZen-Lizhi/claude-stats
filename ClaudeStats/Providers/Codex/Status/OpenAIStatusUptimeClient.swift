import Foundation

protocol OpenAIStatusUptimeFetching: Sendable {
    func fetchUptimeHistories(now: Date) async throws -> OpenAIStatusUptimeSnapshot
}

struct OpenAIStatusUptimeClient: OpenAIStatusUptimeFetching {
    private let endpoint: URL

    init(endpoint: URL = URL(string: "https://status.openai.com/")!) {
        self.endpoint = endpoint
    }

    func fetchUptimeHistories(now: Date = .now) async throws -> OpenAIStatusUptimeSnapshot {
        var request = URLRequest(url: endpoint)
        request.setValue(OpenAIStatusClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw OpenAIStatusClient.ClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIStatusClient.ClientError.http(status: -1)
        }
        Log.network.notice("OpenAI Status uptime fetch \(http.statusCode, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000))ms")

        guard (200...299).contains(http.statusCode) else {
            throw OpenAIStatusClient.ClientError.http(status: http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw OpenAIStatusClient.ClientError.decoding("invalid HTML encoding")
        }

        do {
            return try OpenAIStatusUptimeHTMLParser.parse(html, fetchedAt: now)
        } catch {
            throw OpenAIStatusClient.ClientError.decoding(String(describing: error))
        }
    }
}
