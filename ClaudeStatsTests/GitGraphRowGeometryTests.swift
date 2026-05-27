import Testing
@testable import ClaudeStats

@Suite("GitGraphRowGeometry")
struct GitGraphRowGeometryTests {
    private let geometry = GitGraphRowGeometry(laneSpacing: 14, railPad: 18, avatarGapAfterLane: 20)

    private func c(_ hash: String, _ parents: [String]) -> GraphCommit {
        GraphCommit(hash: hash, parentHashes: parents, refs: [], author: "A", authorEmail: "a@x",
                    date: .distantPast, subject: hash)
    }

    private func byHash(_ layout: GraphLayout) -> [String: GraphLayout.Row] {
        Dictionary(uniqueKeysWithValues: layout.rows.map { ($0.commit.hash, $0) })
    }

    @Test("linear rows keep content after lane zero")
    func linearContentLeading() {
        let layout = GraphLayout.build([c("A", ["B"]), c("B", [])])

        #expect(layout.rows.map { geometry.contentLeading(for: $0) } == [38, 38])
    }

    @Test("rows with crossing lanes shift content after the rightmost active lane")
    func crossingLaneContentLeading() {
        let layout = GraphLayout.build([c("M", ["B", "F"]), c("B", ["A"]), c("F", ["A"]), c("A", [])])
        let rows = byHash(layout)

        #expect(geometry.contentLeading(for: rows["M"]!) == 52)
        #expect(geometry.contentLeading(for: rows["B"]!) == 52)
        #expect(geometry.contentLeading(for: rows["F"]!) == 52)
        #expect(geometry.contentLeading(for: rows["A"]!) == 38)
    }
}
