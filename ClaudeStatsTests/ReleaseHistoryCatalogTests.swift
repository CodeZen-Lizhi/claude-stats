import Foundation
import Testing
@testable import ClaudeStats

@Suite("Release History Catalog")
struct ReleaseHistoryCatalogTests {
    @Test("Entries cover release history from newest to v1.4.0")
    func entriesCoverReleaseHistory() {
        let entries = ReleaseHistoryCatalog.entries

        #expect(!entries.isEmpty)
        #expect(entries.first?.version == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(entries.first { $0.version == "1.5.6" }?.headline == "skip")
        #expect(entries.first { $0.version == "1.5.6" }?.changes == ["skip"])
        #expect(entries.last?.version.contains("1.4.0") == true)
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(entries.allSatisfy { entry in
            !entry.headline.isEmpty
                && !entry.changes.isEmpty
                && entry.changes.allSatisfy { !$0.isEmpty }
        })
    }
}
