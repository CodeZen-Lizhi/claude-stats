import Foundation
@preconcurrency import Network

enum NetworkProxyEvent: Sendable {
    case started(NetworkProxyEndpoint)
    case stopped
    case flowCreated(NetworkFlow)
    case flowUpdated(NetworkFlow)
    case failed(String)
}

/// Compact first-pass proxy adapter inspired by Rockxy's SwiftNIO proxy module.
/// This version keeps the API surface small for Claude Stats while the full
/// helper/MITM path is staged behind the Network UI.
final class NetworkProxyService: @unchecked Sendable {
    typealias EventHandler = @Sendable (NetworkProxyEvent) -> Void

    private let queue = DispatchQueue(label: "com.claudestats.network-proxy")
    private let bodyLimit = 2 * 1024 * 1024
    private var listener: NWListener?
    private var eventHandler: EventHandler?
    private var nextFlowNumber = 1
    private var activeConnections = Set<ObjectIdentifier>()

    func start(preferredPorts: ClosedRange<UInt16>, eventHandler: @escaping EventHandler) throws -> NetworkProxyEndpoint {
        stop()
        self.eventHandler = eventHandler

        var lastError: Error?
        for portValue in preferredPorts {
            do {
                let endpoint = try start(on: portValue)
                emit(.started(endpoint))
                return endpoint
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NetworkProxyError.bindFailed
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            activeConnections.removeAll()
        }
        emit(.stopped)
    }

    private func start(on portValue: UInt16) throws -> NetworkProxyEndpoint {
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            throw NetworkProxyError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let newListener = try NWListener(using: parameters, on: port)
        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.emit(.failed(error.localizedDescription))
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener = newListener
        newListener.start(queue: queue)
        return NetworkProxyEndpoint(host: "127.0.0.1", port: portValue)
    }

    private func accept(_ connection: NWConnection) {
        activeConnections.insert(ObjectIdentifier(connection))
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .cancelled = state, let connection {
                self?.activeConnections.remove(ObjectIdentifier(connection))
            }
        }
        connection.start(queue: queue)
        readInitialRequest(from: connection, buffer: Data())
    }

    private func readInitialRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.emit(.failed(error.localizedDescription))
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }
            if let split = nextBuffer.headerBodySplitIndex {
                let headerData = nextBuffer[..<split.headerEnd]
                let bodyData = nextBuffer[split.bodyStart...]
                self.handleRequest(headerData: Data(headerData), initialBody: Data(bodyData), connection: connection)
            } else if isComplete || nextBuffer.count > 256 * 1024 {
                connection.cancel()
            } else {
                self.readInitialRequest(from: connection, buffer: nextBuffer)
            }
        }
    }

    private func handleRequest(headerData: Data, initialBody: Data, connection: NWConnection) {
        guard let request = HTTPProxyRequest(headerData: headerData, initialBody: initialBody) else {
            sendSimpleResponse(status: 400, reason: "Bad Request", body: "Unable to parse proxy request.", to: connection)
            return
        }

        if request.method.uppercased() == "CONNECT" {
            handleConnect(request, client: connection)
        } else {
            handleHTTP(request, client: connection)
        }
    }

    private func handleHTTP(_ request: HTTPProxyRequest, client: NWConnection) {
        let id = UUID()
        let number = allocateFlowNumber()
        let createdAt = Date()
        let flowRequest = request.capture(bodyLimit: bodyLimit)
        let flow = NetworkFlow(
            id: id,
            number: number,
            createdAt: createdAt,
            completedAt: nil,
            clientName: "Proxy Client",
            flowProtocol: request.url?.scheme?.lowercased() == "https" ? .https : .http,
            state: .active,
            request: flowRequest,
            response: .empty,
            requestBytes: request.body.count,
            responseBytes: 0,
            isSSLIntercepted: false,
            isEdited: false,
            errorDescription: nil
        )
        emit(.flowCreated(flow))

        Task { @concurrent in
            do {
                let result = try await Self.fetch(request: request, bodyLimit: self.bodyLimit)
                var updated = flow
                updated.completedAt = Date()
                updated.state = .completed
                updated.response = result.capture
                updated.responseBytes = result.body.count
                self.emit(.flowUpdated(updated))
                self.send(response: result, to: client)
            } catch {
                var failed = flow
                failed.completedAt = Date()
                failed.state = .failed
                failed.errorDescription = error.localizedDescription
                failed.response = NetworkResponseCapture(statusCode: 502, reason: "Bad Gateway", headers: [], body: NetworkBody(bytes: 0, text: error.localizedDescription, isTruncated: false, contentType: "text/plain"))
                self.emit(.flowUpdated(failed))
                self.sendSimpleResponse(status: 502, reason: "Bad Gateway", body: error.localizedDescription, to: client)
            }
        }
    }

    private func handleConnect(_ request: HTTPProxyRequest, client: NWConnection) {
        let id = UUID()
        let number = allocateFlowNumber()
        let createdAt = Date()
        let flow = NetworkFlow(
            id: id,
            number: number,
            createdAt: createdAt,
            completedAt: nil,
            clientName: "Proxy Client",
            flowProtocol: .tunnel,
            state: .active,
            request: request.capture(bodyLimit: bodyLimit),
            response: .empty,
            requestBytes: 0,
            responseBytes: 0,
            isSSLIntercepted: false,
            isEdited: false,
            errorDescription: nil
        )
        emit(.flowCreated(flow))

        let target = HostPort(request.target, defaultPort: 443)
        guard let target else {
            var failed = flow
            failed.completedAt = Date()
            failed.state = .failed
            failed.response = NetworkResponseCapture(statusCode: 400, reason: "Bad CONNECT target", headers: [], body: .empty)
            emit(.flowUpdated(failed))
            sendSimpleResponse(status: 400, reason: "Bad Request", body: "Invalid CONNECT target.", to: client)
            return
        }

        let upstream = NWConnection(host: NWEndpoint.Host(target.host), port: NWEndpoint.Port(rawValue: target.port)!, using: .tcp)
        upstream.stateUpdateHandler = { [weak self, weak client, weak upstream] state in
            guard let self, let client, let upstream else { return }
            switch state {
            case .ready:
                var updated = flow
                updated.response = NetworkResponseCapture(statusCode: 200, reason: "Connection Established", headers: [], body: .empty)
                self.emit(.flowUpdated(updated))
                client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in
                    self.bridge(from: client, to: upstream)
                    self.bridge(from: upstream, to: client)
                })
            case .failed(let error):
                var failed = flow
                failed.completedAt = Date()
                failed.state = .failed
                failed.errorDescription = error.localizedDescription
                failed.response = NetworkResponseCapture(statusCode: 502, reason: "Bad Gateway", headers: [], body: .empty)
                self.emit(.flowUpdated(failed))
                self.sendSimpleResponse(status: 502, reason: "Bad Gateway", body: error.localizedDescription, to: client)
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func bridge(from source: NWConnection, to target: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                target.send(content: data, completion: .contentProcessed { [weak self] _ in
                    if isComplete || error != nil {
                        source.cancel()
                        target.cancel()
                    } else {
                        self?.bridge(from: source, to: target)
                    }
                })
            } else {
                source.cancel()
                target.cancel()
            }
        }
    }

    private func send(response: HTTPProxyResponse, to connection: NWConnection) {
        var bytes = Data()
        bytes.append(Data("HTTP/1.1 \(response.statusCode) \(response.reason)\r\n".utf8))
        for header in response.headers {
            guard header.name.caseInsensitiveCompare("Transfer-Encoding") != .orderedSame else { continue }
            guard header.name.caseInsensitiveCompare("Content-Length") != .orderedSame else { continue }
            bytes.append(Data("\(header.name): \(header.value)\r\n".utf8))
        }
        bytes.append(Data("Content-Length: \(response.body.count)\r\n".utf8))
        bytes.append(Data("Connection: close\r\n\r\n".utf8))
        bytes.append(response.body)
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendSimpleResponse(status: Int, reason: String, body: String, to connection: NWConnection) {
        let bodyData = Data(body.utf8)
        var bytes = Data()
        bytes.append(Data("HTTP/1.1 \(status) \(reason)\r\n".utf8))
        bytes.append(Data("Content-Type: text/plain; charset=utf-8\r\n".utf8))
        bytes.append(Data("Content-Length: \(bodyData.count)\r\n".utf8))
        bytes.append(Data("Connection: close\r\n\r\n".utf8))
        bytes.append(bodyData)
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func allocateFlowNumber() -> Int {
        let number = nextFlowNumber
        nextFlowNumber += 1
        return number
    }

    private func emit(_ event: NetworkProxyEvent) {
        eventHandler?(event)
    }

    private static func fetch(request: HTTPProxyRequest, bodyLimit: Int) async throws -> HTTPProxyResponse {
        guard let url = request.url else { throw NetworkProxyError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for header in request.headers {
            let lower = header.name.lowercased()
            guard lower != "proxy-connection" && lower != "connection" && lower != "host" else { continue }
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !request.body.isEmpty {
            urlRequest.httpBody = request.body
        }

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
        ]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkProxyError.invalidResponse
        }

        let headers = http.allHeaderFields.compactMap { key, value -> NetworkHeaderPair? in
            guard let name = key as? String else { return nil }
            return NetworkHeaderPair(name: name, value: "\(value)")
        }
        let reason = HTTPReasonPhrase.reason(for: http.statusCode)
        let text = NetworkProxyText.bodyText(from: data, contentType: http.value(forHTTPHeaderField: "Content-Type"), limit: bodyLimit).text
        let capture = NetworkResponseCapture(
            statusCode: http.statusCode,
            reason: reason,
            headers: headers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            body: NetworkBody(bytes: data.count, text: text, isTruncated: data.count > bodyLimit, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        )
        return HTTPProxyResponse(statusCode: http.statusCode, reason: reason, headers: headers, body: data, capture: capture)
    }
}

private enum NetworkProxyError: LocalizedError {
    case bindFailed
    case invalidPort
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .bindFailed: "Unable to bind a local proxy port."
        case .invalidPort: "Invalid proxy port."
        case .invalidURL: "Invalid proxy URL."
        case .invalidResponse: "The upstream server did not return an HTTP response."
        }
    }
}

private struct HTTPProxyRequest: Sendable {
    var method: String
    var target: String
    var httpVersion: String
    var headers: [NetworkHeaderPair]
    var body: Data

    init?(headerData: Data, initialBody: Data) {
        guard let text = String(data: headerData, encoding: .isoLatin1) ?? String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        method = parts[0]
        target = parts[1]
        httpVersion = parts[2]
        headers = lines.dropFirst().compactMap { line in
            guard let idx = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return NetworkHeaderPair(name: name, value: value)
        }
        body = initialBody
    }

    var url: URL? {
        if let absolute = URL(string: target), absolute.scheme != nil {
            return absolute
        }
        guard let host = header(named: "Host") else { return nil }
        return URL(string: "http://\(host)\(target)")
    }

    func header(named name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func capture(bodyLimit: Int) -> NetworkRequestCapture {
        let displayURL: String
        if method.uppercased() == "CONNECT" {
            displayURL = "https://\(target)"
        } else {
            displayURL = url?.absoluteString ?? target
        }
        let contentType = header(named: "Content-Type")
        let bodyText = NetworkProxyText.bodyText(from: body, contentType: contentType, limit: bodyLimit)
        return NetworkRequestCapture(
            method: method,
            url: displayURL,
            httpVersion: httpVersion,
            headers: headers,
            body: NetworkBody(bytes: body.count, text: bodyText.text, isTruncated: bodyText.isTruncated, contentType: contentType)
        )
    }
}

private struct HTTPProxyResponse: Sendable {
    var statusCode: Int
    var reason: String
    var headers: [NetworkHeaderPair]
    var body: Data
    var capture: NetworkResponseCapture
}

private struct HostPort: Sendable {
    var host: String
    var port: UInt16

    init?(_ string: String, defaultPort: UInt16) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let p = UInt16(parts[1]) {
            host = parts[0]
            port = p
        } else if !string.isEmpty {
            host = string
            port = defaultPort
        } else {
            return nil
        }
    }
}

private enum NetworkProxyText {
    static func bodyText(from data: Data, contentType: String?, limit: Int) -> (text: String, isTruncated: Bool) {
        guard !data.isEmpty else { return ("", false) }
        let slice = data.prefix(limit)
        let text = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) ?? "<\(data.count) binary bytes>"
        return (text, data.count > limit)
    }
}

private enum HTTPReasonPhrase {
    static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: "HTTP \(status)"
        }
    }
}

private extension Data {
    var headerBodySplitIndex: (headerEnd: Data.Index, bodyStart: Data.Index)? {
        guard let range = range(of: Data([13, 10, 13, 10])) else { return nil }
        return (range.lowerBound, range.upperBound)
    }
}
