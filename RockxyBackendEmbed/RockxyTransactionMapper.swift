import Foundation

enum RockxyTransactionMapper {
    static func captured(from transaction: HTTPTransaction, sequenceNumber: Int) -> RockxyCapturedTransaction {
        let startedAt = transaction.startedAt ?? transaction.timestamp
        let measuredDuration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration
        let completedAt = transaction.completedAt ?? synthesizedCompletedAt(
            state: transaction.state,
            startedAt: startedAt,
            measuredDuration: measuredDuration
        )

        return RockxyCapturedTransaction(
            id: transaction.id,
            sequenceNumber: transaction.sequenceNumber > 0 ? transaction.sequenceNumber : sequenceNumber,
            timestamp: startedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            measuredDuration: measuredDuration,
            establishmentDuration: transaction.establishmentDuration,
            request: capturedRequest(from: transaction.request),
            response: transaction.response.map(capturedResponse(from:)),
            state: capturedState(from: transaction.state),
            isTLSFailure: transaction.isTLSFailure,
            isWebSocket: transaction.webSocketConnection != nil,
            sourcePort: transaction.sourcePort,
            clientApp: transaction.clientApp,
            clientAttribution: capturedAttribution(from: transaction.clientAttribution),
            matchedRuleName: transaction.matchedRuleName,
            matchedRuleActionSummary: transaction.matchedRuleActionSummary,
            matchedRulePattern: transaction.matchedRulePattern,
            upstreamProxySummary: transaction.upstreamProxySummary,
            upstreamProxyKind: transaction.upstreamProxyKind,
            webSocketFrames: transaction.webSocketConnection?.frames.map(capturedFrame(from:)) ?? []
        )
    }

    private static func synthesizedCompletedAt(
        state: TransactionState,
        startedAt: Date,
        measuredDuration: TimeInterval?
    ) -> Date? {
        switch state {
        case .pending, .active:
            nil
        case .completed, .failed, .blocked:
            measuredDuration.map { startedAt.addingTimeInterval($0) }
        }
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

    private static func capturedAttribution(from attribution: ClientAppAttribution?) -> RockxyClientAttribution? {
        switch attribution {
        case .process:
            .process
        case .userAgent:
            .userAgent
        case .unresolved:
            .unresolved
        case nil:
            nil
        }
    }

    private static func capturedFrame(from frame: WebSocketFrameData) -> RockxyWebSocketFrameSnapshot {
        RockxyWebSocketFrameSnapshot(
            id: frame.id,
            timestamp: frame.timestamp,
            direction: frame.direction == .sent ? .sent : .received,
            opcode: opcodeName(frame.opcode),
            payload: frame.payload,
            isFinal: frame.isFinal
        )
    }

    private static func opcodeName(_ opcode: FrameOpcode) -> String {
        switch opcode {
        case .continuation: "Continuation"
        case .text: "Text"
        case .binary: "Binary"
        case .connectionClose: "Close"
        case .ping: "Ping"
        case .pong: "Pong"
        }
    }
}
