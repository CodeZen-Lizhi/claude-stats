import Foundation
import Testing
@testable import ClaudeStats

@Suite("Transcript render window")
struct TranscriptRenderWindowTests {
    @Test("Large transcripts render the latest bounded window by default")
    func largeTranscriptsRenderLatestWindow() {
        let messages = (0..<5).map { message(id: "\($0)", text: "message \($0)") }
        let index = TranscriptSearchIndex.make(messages: messages, query: "")

        let window = TranscriptRenderWindow.make(messages: messages, searchIndex: index, searchQuery: "", limit: 3)

        #expect(window.messages.map(\.id) == ["2", "3", "4"])
        #expect(window.totalCount == 5)
        #expect(window.mode == .recent(hiddenCount: 2))
    }

    @Test("Searching renders matching messages from the full transcript")
    func searchRendersMatchingMessages() {
        let messages = [
            message(id: "1", text: "plain"),
            message(id: "2", text: "find codex here"),
            message(id: "3", text: "another CODEX match"),
        ]
        let index = TranscriptSearchIndex.make(messages: messages, query: "codex")

        let window = TranscriptRenderWindow.make(messages: messages, searchIndex: index, searchQuery: "codex", limit: 1)

        #expect(window.messages.map(\.id) == ["2", "3"])
        #expect(window.totalCount == 3)
        #expect(window.mode == .search(matchCount: 2))
    }

    private func message(id: String, text: String) -> SessionTranscriptMessage {
        SessionTranscriptMessage(id: id, role: .assistant, text: text, timestamp: nil, model: nil)
    }
}
