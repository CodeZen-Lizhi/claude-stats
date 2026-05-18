import CoreGraphics
import Foundation

enum NotchIslandLayoutPolicy {
    static let horizontalMargin: CGFloat = 16
    static let topOffset: CGFloat = 0

    static func compactSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect) -> CGSize {
        let base: CGSize = switch preset {
        case .compact: CGSize(width: 212, height: 34)
        case .regular: CGSize(width: 246, height: 38)
        case .large: CGSize(width: 284, height: 42)
        }
        return clamped(base, in: screenFrame, expanded: false)
    }

    static func expandedSize(for preset: NotchIslandSizePreset, in screenFrame: CGRect) -> CGSize {
        let base: CGSize = switch preset {
        case .compact: CGSize(width: 520, height: 260)
        case .regular: CGSize(width: 640, height: 340)
        case .large: CGSize(width: 760, height: 420)
        }
        return clamped(base, in: screenFrame, expanded: true)
    }

    static func size(for preset: NotchIslandSizePreset, expanded: Bool, in screenFrame: CGRect) -> CGSize {
        expanded ? expandedSize(for: preset, in: screenFrame) : compactSize(for: preset, in: screenFrame)
    }

    static func frame(in screenFrame: CGRect, preset: NotchIslandSizePreset, expanded: Bool) -> CGRect {
        let size = size(for: preset, expanded: expanded, in: screenFrame)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height - topOffset
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clamped(_ size: CGSize, in screenFrame: CGRect, expanded: Bool) -> CGSize {
        let maximumWidth = max(80, screenFrame.width - horizontalMargin * 2)
        let maximumHeight = expanded ? max(120, screenFrame.height * 0.78) : max(24, screenFrame.height * 0.12)
        return CGSize(
            width: min(size.width, maximumWidth),
            height: min(size.height, maximumHeight)
        )
    }
}
