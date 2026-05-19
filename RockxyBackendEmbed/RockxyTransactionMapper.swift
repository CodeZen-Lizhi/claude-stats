import Foundation

enum RockxyTransactionMapper {
    static func captured(from transaction: HTTPTransaction, sequenceNumber: Int) -> RockxyCapturedTransaction {
        RockxyCapturedTransaction(
            id: transaction.id,
            sequenceNumber: transaction.sequenceNumber > 0 ? transaction.sequenceNumber : sequenceNumber,
            timestamp: transaction.timestamp,
            measuredDuration: transaction.measuredDuration,
            request: capturedRequest(from: transaction.request),
            response: transaction.response.map(capturedResponse(from:)),
            state: capturedState(from: transaction.state),
            isTLSFailure: transaction.isTLSFailure,
            isWebSocket: transaction.webSocketConnection != nil,
            sourcePort: transaction.sourcePort,
            clientApp: transaction.clientApp,
            matchedRuleName: transaction.matchedRuleName,
            upstreamProxySummary: transaction.upstreamProxySummary,
            upstreamProxyKind: transaction.upstreamProxyKind
        )
    }

    private static func capturedRequest(from request: HTTPRequestData) -> RockxyCapturedRequest {
        RockxyCapturedRequest(
            method: request.method,
            url: request.url,
            httpVersion: request.httpVersion,
            headers: request.headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) },
            body: request.body,
            contentType: request.contentType?.rawValue
        )
    }

    private static func capturedResponse(from response: HTTPResponseData) -> RockxyCapturedResponse {
        RockxyCapturedResponse(
            statusCode: response.statusCode,
            statusMessage: response.statusMessage,
            headers: response.headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) },
            body: response.body,
            bodyTruncated: response.bodyTruncated,
            contentType: response.contentType?.rawValue
        )
    }

    private static func capturedState(from state: TransactionState) -> RockxyCapturedTransactionState {
        switch state {
        case .pending:
            .pending
        case .active:
            .active
        case .completed:
            .completed
        case .failed:
            .failed
        case .blocked:
            .blocked
        }
    }
}
