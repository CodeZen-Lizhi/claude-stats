import AppKit

enum GitDiffBlockVisualState: Hashable {
    case normal
    case selected
}

struct GitDiffRenderPalette {
    let background: NSColor
    let paneBackground: NSColor
    let separator: NSColor
    let lineNumber: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let additionFill: NSColor
    let additionSelectedFill: NSColor
    let additionStroke: NSColor
    let deletionFill: NSColor
    let deletionSelectedFill: NSColor
    let deletionStroke: NSColor
    let modificationFill: NSColor
    let modificationSelectedFill: NSColor
    let modificationStroke: NSColor
    let hunkHeaderFill: NSColor
    let hunkHeaderHoverFill: NSColor
    let overviewTrackFill: NSColor
    let inlineAdditionFill: NSColor
    let inlineDeletionFill: NSColor

    static let standard = GitDiffRenderPalette(
        background: .textBackgroundColor,
        paneBackground: .textBackgroundColor,
        separator: NSColor.separatorColor.withAlphaComponent(0.42),
        lineNumber: .secondaryLabelColor,
        primaryText: .labelColor,
        secondaryText: .secondaryLabelColor,
        additionFill: hexColor(0xF7FFF5),
        additionSelectedFill: hexColor(0xEEFFEA),
        additionStroke: hexColor(0xBFE8B8),
        deletionFill: hexColor(0xFFF0EF),
        deletionSelectedFill: hexColor(0xFFDFDE),
        deletionStroke: hexColor(0xF2B6B4),
        modificationFill: hexColor(0xF2FAFF),
        modificationSelectedFill: hexColor(0xE6F4FF),
        modificationStroke: hexColor(0xA8D8FF),
        hunkHeaderFill: hexColor(0xF4F4F4),
        hunkHeaderHoverFill: hexColor(0xECECEC),
        overviewTrackFill: hexColor(0xF3F3F3),
        inlineAdditionFill: hexColor(0xEEFFEA),
        inlineDeletionFill: hexColor(0xFFDFDE)
    )

    private static func hexColor(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func rowFill(for kind: DiffLine.Kind, state: GitDiffBlockVisualState = .normal) -> NSColor {
        switch kind {
        case .addition:
            return blockFill(for: .addition, state: state)
        case .deletion:
            return blockFill(for: .deletion, state: state)
        case .hunkHeader:
            return hunkHeaderFill
        default:
            return .clear
        }
    }

    func blockFill(for kind: GitDiffVisualKind, state: GitDiffBlockVisualState = .normal) -> NSColor {
        switch kind {
        case .addition:
            return state == .selected ? additionSelectedFill : additionFill
        case .deletion:
            return state == .selected ? deletionSelectedFill : deletionFill
        case .modification:
            return state == .selected ? modificationSelectedFill : modificationFill
        case .hunkHeader:
            return hunkHeaderFill
        case .context:
            return .clear
        }
    }

    func connectorFill(for kind: GitDiffVisualKind, state: GitDiffBlockVisualState = .normal) -> NSColor {
        blockFill(for: kind, state: state)
    }

    func overviewFill(for kind: GitDiffVisualKind, state: GitDiffBlockVisualState = .normal) -> NSColor {
        blockFill(for: kind, state: state)
    }

    func blockStroke(for kind: GitDiffVisualKind) -> NSColor {
        switch kind {
        case .addition:
            return additionStroke
        case .deletion:
            return deletionStroke
        case .modification:
            return modificationStroke
        case .hunkHeader:
            return hunkHeaderHoverFill
        case .context:
            return .clear
        }
    }

    func textColor(for kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .fileHeader, .hunkHeader:
            return secondaryText
        default:
            return primaryText
        }
    }

    func inlineFill(for kind: DiffInlineSpan.Kind) -> NSColor {
        switch kind {
        case .addition:
            return inlineAdditionFill
        case .deletion:
            return inlineDeletionFill
        }
    }
}
