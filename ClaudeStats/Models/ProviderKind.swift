import SwiftUI

/// The AI coding tools Claude Stats can read. ``claude`` is fully implemented;
/// ``codex`` reads `~/.codex/sessions/`; ``gemini`` / ``kimi`` / ``minimax``
/// are recognised (UI, settings, asset) but their on-disk log formats aren't
/// parsed yet — their providers return no sessions.
///
/// `allCases` order is the canonical display order (used by the platform
/// switcher bar and the settings list).
enum ProviderKind: String, CaseIterable, Sendable, Identifiable, Hashable {
    case claude
    case codex
    case gemini
    case kimi
    case minimax

    var id: String { rawValue }

    /// Full name for tooltips and settings rows.
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        case .gemini: "Gemini"
        case .kimi: "Kimi CLI"
        case .minimax: "MiniMax"
        }
    }

    /// Short name for the panel header (`"<shortName> STATS"`).
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .kimi: "Kimi"
        case .minimax: "MiniMax"
        }
    }

    /// Name of the colour-logo image set in `Assets.xcassets/Providers/` — used
    /// in Settings.
    var assetName: String {
        switch self {
        case .claude: "claudecode-color"
        case .codex: "codex-color"
        case .gemini: "gemini-color"
        case .kimi: "kimi"   // Kimi ships a single logo used in both places.
        case .minimax: "minimax-color"
        }
    }

    /// Name of the monochrome (template-rendered) logo image set — used in the
    /// panel's platform switcher so all logos read uniformly.
    var monochromeAssetName: String {
        switch self {
        case .claude: "claudecode"
        case .codex: "codex"
        case .gemini: "gemini"
        case .kimi: "kimi"
        case .minimax: "minimax"
        }
    }

    /// SF Symbol used as a fallback if the logo asset is unavailable.
    var iconSystemName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        case .kimi: "moon.stars"
        case .minimax: "bolt"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.45, blue: 0.20)
        case .codex: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .gemini: Color(red: 0.19, green: 0.53, blue: 1.0)
        case .kimi: Color(red: 0.20, green: 0.20, blue: 0.22)
        case .minimax: Color(red: 0.92, green: 0.30, blue: 0.26)
        }
    }
}
