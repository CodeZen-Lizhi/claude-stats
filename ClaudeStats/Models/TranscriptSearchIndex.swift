import Foundation

struct TranscriptSearchMatch: Equatable, Sendable, Identifiable {
    let messageID: String
    let range: Range<String.Index>
    let ordinal: Int

    var id: String { "\(messageID)-\(ordinal)" }
}

struct TranscriptSearchIndex: Equatable, Sendable {
    let query: String
    let matches: [TranscriptSearchMatch]

    var isEmpty: Bool { matches.isEmpty }
    var count: Int { matches.count }

    static func make(messages: [SessionTranscriptMessage], query: String) -> TranscriptSearchIndex {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranscriptSearchIndex(query: "", matches: [])
        }

        var matches: [TranscriptSearchMatch] = []
        for message in messages {
            var searchStart = message.text.startIndex
            while searchStart < message.text.endIndex,
                  let range = message.text.range(
                    of: trimmed,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<message.text.endIndex
                  ) {
                matches.append(TranscriptSearchMatch(messageID: message.id, range: range, ordinal: matches.count))
                searchStart = range.upperBound
            }
        }
        return TranscriptSearchIndex(query: trimmed, matches: matches)
    }

    func matches(for messageID: String) -> [TranscriptSearchMatch] {
        matches.filter { $0.messageID == messageID }
    }

    func selectedMessageID(selectedOrdinal: Int?) -> String? {
        guard let selectedOrdinal, matches.indices.contains(selectedOrdinal) else { return nil }
        return matches[selectedOrdinal].messageID
    }
}
