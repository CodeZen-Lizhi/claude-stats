import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git diff interaction hit testing")
struct GitDiffInteractionHitTestingTests {
    @Test("Split panes hit old and new block rects")
    func splitPaneRectsHitChangeBlock() {
        let region = GitDiffInteractionRegion(
            id: "change-1",
            visualKind: .modification,
            rects: [
                CGRect(x: 0, y: 20, width: 120, height: 30),
                CGRect(x: 200, y: 20, width: 120, height: 30)
            ]
        )

        #expect(GitDiffInteractionHitTesting.hitTest([region], at: CGPoint(x: 24, y: 34)) == "change-1")
        #expect(GitDiffInteractionHitTesting.hitTest([region], at: CGPoint(x: 224, y: 34)) == "change-1")
        #expect(GitDiffInteractionHitTesting.hitTest([region], at: CGPoint(x: 160, y: 34)) == nil)
    }

    @Test("Blocks span rect connects both panes through the gutter")
    func blocksSpanRectConnectsPanesThroughGutter() {
        let columns = GitDiffRenderColumns(
            leftPane: CGRect(x: 0, y: 0, width: 120, height: 200),
            gutter: CGRect(x: 120, y: 0, width: 40, height: 200),
            rightPane: CGRect(x: 160, y: 0, width: 120, height: 200),
            overviewLane: CGRect(x: 300, y: 0, width: 20, height: 200)
        )
        let block = GitDiffRenderBlock(
            id: "block-change",
            segmentIndex: 0,
            visualKind: .addition,
            oldContentRect: CGRect(x: 0, y: 20, width: 0, height: 54),
            newContentRect: CGRect(x: 0, y: 20, width: 0, height: 54),
            oldIsAnchor: false,
            newIsAnchor: false
        )
        let rect = GitDiffBlockGeometry.linearSpanRect(for: block, columns: columns)
        let region = GitDiffInteractionRegion(id: block.id, visualKind: block.visualKind, rects: [rect])

        #expect(rect.minX == columns.leftPane.minX)
        #expect(rect.maxX == columns.rightPane.maxX)
        #expect(GitDiffInteractionHitTesting.hitTest([region], at: CGPoint(x: columns.gutter.midX, y: 40)) == block.id)
    }

    @Test("Fluid connector rect hits the same change block")
    func fluidConnectorRectHitsChangeBlock() {
        let region = GitDiffInteractionRegion(
            id: "fluid-change",
            visualKind: .addition,
            rects: [
                CGRect(x: 0, y: 40, width: 120, height: 18),
                CGRect(x: 220, y: 70, width: 120, height: 72),
                CGRect(x: 119, y: 40, width: 102, height: 102)
            ]
        )

        #expect(GitDiffInteractionHitTesting.hitTest([region], at: CGPoint(x: 170, y: 84)) == "fluid-change")
    }

    @Test("Later regions win overlap hit testing")
    func laterRegionsWinOverlapHitTesting() {
        let bottom = GitDiffInteractionRegion(
            id: "bottom",
            visualKind: .deletion,
            rects: [CGRect(x: 0, y: 0, width: 40, height: 40)]
        )
        let top = GitDiffInteractionRegion(
            id: "top",
            visualKind: .modification,
            rects: [CGRect(x: 10, y: 10, width: 40, height: 40)]
        )

        #expect(GitDiffInteractionHitTesting.hitTest([bottom, top], at: CGPoint(x: 20, y: 20)) == "top")
    }
}
