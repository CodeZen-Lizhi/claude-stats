import AppKit
import CoreGraphics
import Foundation

enum NotchIslandLayoutPolicy {
    static let horizontalMargin: CGFloat = AtollNotchGeometry.horizontalMargin
    static let topOffset: CGFloat = 0

    static func compactSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect) -> CGSize {
        AtollNotchGeometry.closedSize(
            in: screenFrame,
            safeAreaTop: 0,
            visibleMaxY: screenFrame.maxY - AtollNotchGeometry.closedFallbackHeight
        )
    }

    static func expandedSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect) -> CGSize {
        AtollNotchGeometry.openSize(for: preset, in: screenFrame)
    }

    static func size(for preset: NotchIslandSizePreset, expanded: Bool, in screenFrame: CGRect) -> CGSize {
        expanded ? expandedSize(for: preset, in: screenFrame) : compactSize(for: preset, in: screenFrame)
    }

    static func frame(in screenFrame: CGRect, preset: NotchIslandSizePreset, expanded: Bool) -> CGRect {
        let closedSize = compactSize(for: preset, in: screenFrame)
        return AtollNotchGeometry.visualFrame(
            in: screenFrame,
            preset: preset,
            expanded: expanded,
            closedSize: closedSize
        )
    }
}
