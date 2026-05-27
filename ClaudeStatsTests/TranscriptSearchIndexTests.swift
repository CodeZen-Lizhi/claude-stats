import Foundation
import Testing
@testable import ClaudeStats

@Suite("Transcript search index")
struct TranscriptSearchIndexTests {
    @Test("Search is case-insensitive and tracks match order")
    func searchIsCaseInsensitiveAndTracksMatchOrder() {
        let messages = [
            message(id: "1", text: "Hello Codex, hello transcript"),
            message(id: "2", text: "CODEX can search code blocks"),
        ]

        let index = TranscriptSearchIndex.make(messages: messages, query: "codex")

        #expect(index.count == 2)
        #expect(index.matches.map(\.messageID) == ["1", "2"])
        #expect(index.selectedMessageID(selectedOrdinal: 1) == "2")
    }

    @Test("Empty and whitespace queries produce no matches")
    func emptyAndWhitespaceQueriesProduceNoMatches() {
        let index = TranscriptSearchIndex.make(messages: [message(id: "1", text: "Codex")], query: "   ")

        #expect(index.isEmpty)
        #expect(index.query == "")
    }

    private func message(id: String, text: String) -> SessionTranscriptMessage {
        SessionTranscriptMessage(id: id, role: .assistant, text: text, timestamp: nil, model: nil)
    }
}
