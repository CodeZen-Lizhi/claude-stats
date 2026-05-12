import SwiftUI

/// The AI coding tools Claude Stats can read. ``claude`` is fully implemented;
/// ``codex`` reads `~/.codex/sessions/`; ``antigravity`` / ``kimi`` /
/// ``minimax`` are recognised (UI, settings, asset) but their on-disk log
/// formats aren't parsed yet — their providers return no sessions.
///
/// `allCases` order is the canonical display order (used by the platform
/// switcher bar and the settings list).
enum ProviderKind: String, CaseIterable, Sendable, Identifiable, Hashable {
    case claude
    case codex
    case antigravity
    case kimi
    case minimax

    var id: String { rawValue }

    /// Full name for tooltips and settings rows.
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        case .antigravity: "Antigravity"
        case .kimi: "Kimi CLI"
        case .minimax: "MiniMax"
        }
    }

    /// Short name for the panel header (`"<shortName> STATS"`).
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .kimi: "Kimi"
        case .minimax: "MiniMax"
        }
    }

    /// Name of the colour-logo image set in `Assets.xcassets/Providers/`.
    var assetName: String {
        switch self {
        case .claude: "claudecode-color"
        case .codex: "codex-color"
        case .antigravity: "antigravity-color"
        case .kimi: "kimi-color"
        case .minimax: "minimax-color"
        }
    }

    /// SF Symbol used as a fallback if the logo asset is unavailable.
    var iconSystemName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "arrow.up.forward"
        case .kimi: "moon.stars"
        case .minimax: "bolt"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.45, blue: 0.20)
        case .codex: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .antigravity: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .kimi: Color(red: 0.20, green: 0.20, blue: 0.22)
        case .minimax: Color(red: 0.92, green: 0.30, blue: 0.26)
        }
    }
}
