import SwiftUI

/// The user-chosen colour scheme for the Dashboard's Overlap heatmap. Three
/// presets cover the trade-off space between "fits the app's warm chrome",
/// "uses one hue only", and "looks like a contribution-graph diff".
enum OverlapPalette: String, CaseIterable, Identifiable, Sendable {
    /// Both = warm orange accent; Local-only = green; GitHub-only = blue;
    /// Neither = muted grey. Reuses ``GitPalette`` so it sits inside the app
    /// chrome.
    case appCohesive
    /// Both = saturated accent; Local-only / GitHub-only = lower-opacity
    /// accent (GitHub-only adds a dashed border so the two single-source
    /// states stay distinguishable); Neither = muted grey.
    case accentOnly
    /// Classic GitHub-diff palette — green / orange / blue / grey.
    case githubClassic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appCohesive: "App palette"
        case .accentOnly: "Accent only"
        case .githubClassic: "GitHub classic"
        }
    }

    func color(for state: OverlapStats.DayState) -> Color {
        switch self {
        case .appCohesive:
            switch state {
            case .both: return .stxAccent
            case .localOnly: return GitPalette.add
            case .githubOnly: return GitPalette.head
            case .neither: return Color.primary.opacity(0.08)
            }
        case .accentOnly:
            switch state {
            case .both: return .stxAccent
            case .localOnly: return Color.stxAccent.opacity(0.45)
            case .githubOnly: return Color.stxAccent.opacity(0.20)
            case .neither: return Color.primary.opacity(0.08)
            }
        case .githubClassic:
            switch state {
            case .both: return Color(red: 0.25, green: 0.77, blue: 0.39)
            case .localOnly: return Color(red: 0.98, green: 0.52, blue: 0.00)
            case .githubOnly: return Color(red: 0.47, green: 0.75, blue: 1.00)
            case .neither: return Color(red: 0.92, green: 0.93, blue: 0.94)
            }
        }
    }

    /// Whether the cell should render a dashed border for this state (used
    /// only by the accent-only palette to distinguish GitHub-only from
    /// Local-only when both are lower-opacity accent).
    func dashedBorder(for state: OverlapStats.DayState) -> Bool {
        switch self {
        case .accentOnly where state == .githubOnly: return true
        default: return false
        }
    }
}
