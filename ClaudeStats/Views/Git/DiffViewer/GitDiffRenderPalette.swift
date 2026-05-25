import AppKit

struct GitDiffRenderPalette {
    let background: NSColor
    let paneBackground: NSColor
    let separator: NSColor
    let lineNumber: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let additionFill: NSColor
    let deletionFill: NSColor
    let modificationFill: NSColor
    let hunkHeaderFill: NSColor
    let hunkHeaderHoverFill: NSColor
    let inlineAdditionFill: NSColor
    let inlineDeletionFill: NSColor

    static let standard = GitDiffRenderPalette(
        background: .textBackgroundColor,
        paneBackground: .textBackgroundColor,
        separator: NSColor.separatorColor.withAlphaComponent(0.42),
        lineNumber: .secondaryLabelColor,
        primaryText: .labelColor,
        secondaryText: .secondaryLabelColor,
        additionFill: hexColor(0xEEFFEA),
        deletionFill: hexColor(0xFFDFDE),
        modificationFill: hexColor(0xE6F4FF),
        hunkHeaderFill: hexColor(0xF4F4F4),
        hunkHeaderHoverFill: hexColor(0xECECEC),
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

    func rowFill(for kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .addition:
            return additionFill
        case .deletion:
            return deletionFill
        case .hunkHeader:
            return hunkHeaderFill
        default:
            return .clear
        }
    }

    func blockFill(for kind: GitDiffVisualKind) -> NSColor {
        switch kind {
        case .addition:
            return additionFill
        case .deletion:
            return deletionFill
        case .modification:
            return modificationFill
        case .hunkHeader:
            return hunkHeaderFill
        case .context:
            return .clear
        }
    }

    func connectorFill(for kind: GitDiffVisualKind) -> NSColor {
        blockFill(for: kind)
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
