import SwiftUI

/// The AI CLIs Claude Stats knows how to read. Today only ``claude`` is
/// implemented; ``codex`` / ``gemini`` are placeholders for when their
/// providers land under `Providers/`.
enum ProviderKind: String, CaseIterable, Sendable, Identifiable, Hashable {
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        }
    }

    /// SF Symbol used in lieu of a bundled brand icon.
    var iconSystemName: String {
        switch self {
        case .claude: "sparkles"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.45, blue: 0.20)
        }
    }
}
