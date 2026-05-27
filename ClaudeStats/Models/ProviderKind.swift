import SwiftUI

/// The AI coding tool Claude Stats can read.
///
/// The app is intentionally Codex-only, while still routing scanning, parsing,
/// and display through the provider abstraction.
enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case codex

    var id: String { rawValue }

    /// Full name for tooltips and settings rows.
    var displayName: String {
        "OpenAI Codex"
    }

    /// Short name for the panel header (`"<shortName> STATS"`).
    var shortName: String {
        "Codex"
    }

    /// Name of the colour-logo image set in `Assets.xcassets/Providers/` — used
    /// in Settings.
    var assetName: String {
        "codex-logo"
    }

    /// Name of the monochrome (template-rendered) logo image set.
    var monochromeAssetName: String {
        "codex"
    }

    /// SF Symbol used as a fallback if the logo asset is unavailable.
    var iconSystemName: String {
        "chevron.left.forwardslash.chevron.right"
    }

    var accentColor: Color {
        Color(red: 0.10, green: 0.10, blue: 0.12)
    }
}
