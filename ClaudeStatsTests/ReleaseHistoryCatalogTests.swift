import Testing
@testable import ClaudeStats

@Suite("Release History Catalog")
struct ReleaseHistoryCatalogTests {
    @Test("Entries cover release history from newest to v1.4.0")
    func entriesCoverReleaseHistory() {
        let entries = ReleaseHistoryCatalog.entries

        #expect(!entries.isEmpty)
        #expect(entries.first?.version == "1.4.9")
        #expect(entries.last?.version.contains("1.4.0") == true)
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(entries.allSatisfy { entry in
            !entry.headline.isEmpty
                && !entry.changes.isEmpty
                && entry.changes.allSatisfy { !$0.isEmpty }
        })
    }
}
