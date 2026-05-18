import Foundation

struct ReleaseHistoryEntry: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let date: String
    let headline: String
    let changes: [String]

    init(version: String, date: String, headline: String, changes: [String]) {
        self.id = version
        self.version = version
        self.date = date
        self.headline = headline
        self.changes = changes
    }
}

enum ReleaseHistoryCatalog {
    static let entries: [ReleaseHistoryEntry] = generatedEntries
}
