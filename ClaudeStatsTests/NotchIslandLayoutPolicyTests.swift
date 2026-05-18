import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("NotchIslandLayoutPolicy")
struct NotchIslandLayoutPolicyTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("Compact frame is centered on the top edge")
    func compactFrameIsTopCentered() {
        let frame = NotchIslandLayoutPolicy.frame(in: screen, preset: .regular, expanded: false)

        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.size == NotchIslandLayoutPolicy.compactSize(for: .regular, in: screen))
    }

    @Test("Expanded frame keeps the top edge fixed")
    func expandedFrameKeepsTopEdge() {
        let compact = NotchIslandLayoutPolicy.frame(in: screen, preset: .regular, expanded: false)
        let expanded = NotchIslandLayoutPolicy.frame(in: screen, preset: .regular, expanded: true)

        #expect(expanded.midX == compact.midX)
        #expect(expanded.maxY == compact.maxY)
        #expect(expanded.width > compact.width)
        #expect(expanded.height > compact.height)
    }

    @Test("Sizes clamp to small displays")
    func sizesClampToSmallDisplays() {
        let small = CGRect(x: 0, y: 0, width: 280, height: 180)
        let compact = NotchIslandLayoutPolicy.frame(in: small, preset: .large, expanded: false)
        let expanded = NotchIslandLayoutPolicy.frame(in: small, preset: .large, expanded: true)

        #expect(compact.minX >= small.minX + NotchIslandLayoutPolicy.horizontalMargin)
        #expect(compact.maxX <= small.maxX - NotchIslandLayoutPolicy.horizontalMargin)
        #expect(expanded.minX >= small.minX + NotchIslandLayoutPolicy.horizontalMargin)
        #expect(expanded.maxX <= small.maxX - NotchIslandLayoutPolicy.horizontalMargin)
        #expect(expanded.maxY == small.maxY)
    }
}
