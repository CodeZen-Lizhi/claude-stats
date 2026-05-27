import Foundation

struct TranscriptRenderWindow: Equatable, Sendable {
    static let defaultLimit = 250

    enum Mode: Equatable, Sendable {
        case all
        case recent(hiddenCount: Int)
        case search(matchCount: Int)
    }

    let messages: [SessionTranscriptMessage]
    let totalCount: Int
    let mode: Mode

    static func make(
        messages: [SessionTranscriptMessage],
        searchIndex: TranscriptSearchIndex,
        searchQuery: String,
        limit: Int = defaultLimit
    ) -> TranscriptRenderWindow {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty else {
            let matchedIDs = Set(searchIndex.matches.map(\.messageID))
            return TranscriptRenderWindow(
                messages: messages.filter { matchedIDs.contains($0.id) },
                totalCount: messages.count,
                mode: .search(matchCount: searchIndex.count)
            )
        }

        guard messages.count > limit else {
            return TranscriptRenderWindow(messages: messages, totalCount: messages.count, mode: .all)
        }

        return TranscriptRenderWindow(
            messages: Array(messages.suffix(limit)),
            totalCount: messages.count,
            mode: .recent(hiddenCount: messages.count - limit)
        )
    }
}
