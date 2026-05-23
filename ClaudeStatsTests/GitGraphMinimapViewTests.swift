import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("GitGraphMinimapView")
struct GitGraphMinimapViewTests {

    @Test("target bucket counts follow width bands")
    func targetBucketCounts() {
        #expect(GitGraphMinimapView.targetMaxBuckets(for: 320) == 80)
        #expect(GitGraphMinimapView.targetMaxBuckets(for: 520) == 120)
        #expect(GitGraphMinimapView.targetMaxBuckets(for: 900) == 160)
    }

    @Test("plot layout keeps edge selection and markers inside canvas bounds")
    func plotLayoutBounds() {
        let size = CGSize(width: 100, height: 48)
        let layout = GitGraphMinimapPlotLayout(size: size)
        let firstMarker = GitGraphMinimapData.Marker(
            kind: .head,
            label: "HEAD",
            hash: "a",
            bucketStart: Date(timeIntervalSince1970: 0),
            priority: .primary
        )
        let lastMarker = GitGraphMinimapData.Marker(
            kind: .workingTree,
            label: "Working Tree",
            hash: nil,
            bucketStart: Date(timeIntervalSince1970: 1),
            priority: .primary
        )

        #expect(layout.xPosition(index: 0, count: 2) == GitGraphMinimapPlotLayout.horizontalInset)
        #expect(layout.xPosition(index: 1, count: 2) == size.width - GitGraphMinimapPlotLayout.horizontalInset)
        expectInside(layout.selectedDotRect(index: 0, count: 2), size: size)
        expectInside(layout.selectedDotRect(index: 1, count: 2), size: size)
        expectInside(layout.hoverDotRect(index: 0, count: 2), size: size)
        expectInside(layout.hoverDotRect(index: 1, count: 2), size: size)
        expectInside(layout.markerRect(index: 0, count: 2, marker: firstMarker), size: size)
        expectInside(layout.markerRect(index: 1, count: 2, marker: lastMarker), size: size)
    }

    @Test("plot layout hit testing clamps to edge buckets")
    func plotLayoutHitTesting() throws {
        let layout = GitGraphMinimapPlotLayout(size: CGSize(width: 100, height: 48))
        #expect(layout.bucketIndex(at: GitGraphMinimapPlotLayout.horizontalInset, count: 5) == 0)
        #expect(layout.bucketIndex(at: 100 - GitGraphMinimapPlotLayout.horizontalInset, count: 5) == 4)
        #expect(layout.bucketIndex(at: -20, count: 5) == 0)
        #expect(layout.bucketIndex(at: 120, count: 5) == 4)
        #expect(layout.bucketIndex(at: 50, count: 5) == 2)
    }

    @Test("selection indicator remains stronger than hover preview")
    func selectionIndicatorDominance() {
        let layout = GitGraphMinimapPlotLayout(size: CGSize(width: 120, height: 48))
        let selected = layout.selectedDotRect(index: 2, count: 5)
        let hover = layout.hoverDotRect(index: 2, count: 5)

        #expect(GitGraphMinimapPlotLayout.selectedDotRadius > GitGraphMinimapPlotLayout.hoverDotRadius)
        #expect(selected.width > hover.width)
        #expect(selected.height > hover.height)
    }

    private func expectInside(_ rect: CGRect, size: CGSize) {
        #expect(rect.minX >= 0)
        #expect(rect.minY >= 0)
        #expect(rect.maxX <= size.width)
        #expect(rect.maxY <= size.height)
    }
}
