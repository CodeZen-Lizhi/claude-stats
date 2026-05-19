import AppKit
import Foundation

struct NetworkRequestOperationService: Sendable {
    func replayDraft(from flow: NetworkFlow, source: NetworkReplaySessionSource = .flow) -> NetworkReplaySession {
        NetworkReplaySession(
            title: title(for: flow, source: source),
            source: source,
            originalFlowID: flow.id,
            draft: NetworkReplayDraft(
                sourceFlowID: flow.id,
                method: flow.request.method,
                url: flow.request.url,
                headers: flow.request.headers,
                bodyText: flow.request.body.text,
                contentType: flow.request.body.contentType
            )
        )
    }

    func composeSession() -> NetworkReplaySession {
        NetworkReplaySession(
            title: "New Request",
            source: .compose,
            originalFlowID: nil,
            draft: NetworkReplayDraft(
                sourceFlowID: UUID(),
                method: "GET",
                url: "https://example.com/",
                headers: [NetworkHeaderPair(name: "Accept", value: "*/*")],
                bodyText: "",
                contentType: nil
            )
        )
    }

    func export(_ flow: NetworkFlow, format: NetworkRequestExportFormat) -> String {
        switch format {
        case .har:
            har(for: [flow])
        case .curl:
            curl(for: flow)
        case .rawRequest:
            rawRequest(for: flow)
        case .rawResponse:
            rawResponse(for: flow)
        }
    }

    func export(_ flows: [NetworkFlow], format: NetworkRequestExportFormat) -> String {
        switch format {
        case .har:
            har(for: flows)
        case .curl:
            flows.map(curl(for:)).joined(separator: "\n")
        case .rawRequest:
            flows.map(rawRequest(for:)).joined(separator: "\n\n")
        case .rawResponse:
            flows.map(rawResponse(for:)).joined(separator: "\n\n")
        }
    }

    func importRequest(_ text: String, format: NetworkRequestImportFormat) throws -> NetworkReplaySession {
        switch format {
        case .curl:
            return try importCurl(text)
        case .rawHTTP:
            return try importRawHTTP(text)
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func curl(for flow: NetworkFlow) -> String {
        var parts = ["curl", "-X", shellQuote(flow.request.method), shellQuote(flow.request.url)]
        for header in flow.request.headers {
            parts += ["-H", shellQuote("\(header.name): \(header.value)")]
        }
        if !flow.request.body.text.isEmpty {
            parts += ["--data-raw", shellQuote(flow.request.body.text)]
        }
        return parts.joined(separator: " ")
    }

    func rawRequest(for flow: NetworkFlow) -> String {
        let head = "\(flow.request.method) \(flow.request.url) \(flow.request.httpVersion)"
        return ([head] + flow.request.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
            + "\n\n"
            + flow.request.body.text
    }

    func rawResponse(for flow: NetworkFlow) -> String {
        let head = "HTTP \(flow.response.statusCode.map(String.init) ?? "-") \(flow.response.reason)"
        return ([head] + flow.response.headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
            + "\n\n"
            + flow.response.body.text
    }

    func har(for flows: [NetworkFlow]) -> String {
        let entries = flows.map { flow -> [String: Any] in
            [
                "startedDateTime": ISO8601DateFormatter().string(from: flow.createdAt),
                "time": flow.duration * 1_000,
                "request": [
                    "method": flow.request.method,
                    "url": flow.request.url,
                    "httpVersion": flow.request.httpVersion,
                    "headers": flow.request.headers.map { ["name": $0.name, "value": $0.value] },
                    "queryString": queryItems(for: flow.request.url),
                    "headersSize": -1,
                    "bodySize": flow.requestBytes,
                    "postData": [
                        "mimeType": flow.request.body.contentType ?? "",
                        "text": flow.request.body.text,
                    ],
                ],
                "response": [
                    "status": flow.response.statusCode ?? 0,
                    "statusText": flow.response.reason,
                    "httpVersion": "HTTP/1.1",
                    "headers": flow.response.headers.map { ["name": $0.name, "value": $0.value] },
                    "content": [
                        "size": flow.responseBytes,
                        "mimeType": flow.response.body.contentType ?? "",
                        "text": flow.response.body.text,
                    ],
                    "redirectURL": "",
                    "headersSize": -1,
                    "bodySize": flow.responseBytes,
                ],
            ]
        }
        let object: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "Claude Stats", "version": "1.0"],
                "entries": entries,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func title(for flow: NetworkFlow, source: NetworkReplaySessionSource) -> String {
        switch source {
        case .flow:
            "\(flow.request.method.uppercased()) \(flow.domainDisplay)"
        case .compose:
            "New Request"
        case .importText:
            "Imported Request"
        }
    }

    private func importCurl(_ text: String) throws -> NetworkReplaySession {
        let tokens = shellTokens(text)
        guard !tokens.isEmpty, tokens.first == "curl" else {
            throw NetworkRequestOperationError.unsupportedImport("Paste a command that starts with curl.")
        }

        var method = "GET"
        var url = ""
        var headers: [NetworkHeaderPair] = []
        var body = ""
        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "-X", "--request":
                index += 1
                if index < tokens.count { method = tokens[index] }
            case "-H", "--header":
                index += 1
                if index < tokens.count {
                    let parts = tokens[index].split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        headers.append(NetworkHeaderPair(
                            name: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines),
                            value: String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                    }
                }
            case "-d", "--data", "--data-raw", "--data-binary":
                index += 1
                if index < tokens.count {
                    body = tokens[index]
                    if method == "GET" { method = "POST" }
                }
            default:
                if !token.hasPrefix("-"), url.isEmpty {
                    url = token
                }
            }
            index += 1
        }

        guard URL(string: url) != nil else {
            throw NetworkRequestOperationError.unsupportedImport("The cURL command does not contain a valid URL.")
        }
        var session = composeSession()
        session.title = "Imported cURL"
        session.source = .importText
        session.draft.method = method.uppercased()
        session.draft.url = url
        session.draft.headers = headers
        session.draft.bodyText = body
        session.draft.contentType = headers.first {
            $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        return session
    }

    private func importRawHTTP(_ text: String) throws -> NetworkReplaySession {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        guard let headerBlock = parts.first else {
            throw NetworkRequestOperationError.unsupportedImport("Raw HTTP request is empty.")
        }
        let lines = headerBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.first?.split(separator: " "), start.count >= 2 else {
            throw NetworkRequestOperationError.unsupportedImport("Raw HTTP request line is invalid.")
        }
        let method = String(start[0]).uppercased()
        let path = String(start[1])
        let headers = lines.dropFirst().compactMap { line -> NetworkHeaderPair? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return NetworkHeaderPair(
                name: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines),
                value: String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let host = headers.first { $0.name.caseInsensitiveCompare("Host") == .orderedSame }?.value ?? ""
        let url = path.hasPrefix("http") ? path : "https://\(host)\(path)"
        guard URL(string: url) != nil else {
            throw NetworkRequestOperationError.unsupportedImport("Raw HTTP request does not contain a valid host or URL.")
        }
        var session = composeSession()
        session.title = "Imported HTTP"
        session.source = .importText
        session.draft.method = method
        session.draft.url = url
        session.draft.headers = headers
        session.draft.bodyText = parts.dropFirst().joined(separator: "\n\n")
        session.draft.contentType = headers.first {
            $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        return session
    }

    private func queryItems(for urlString: String) -> [[String: String]] {
        guard let components = URLComponents(string: urlString) else { return [] }
        return (components.queryItems ?? []).map { ["name": $0.name, "value": $0.value ?? ""] }
    }

    private func shellTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in text {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func shellQuote(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum NetworkRequestOperationError: LocalizedError, Sendable {
    case unsupportedImport(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedImport(let message):
            message
        }
    }
}
