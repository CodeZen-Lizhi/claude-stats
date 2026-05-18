import Foundation

struct ReleaseHistoryEntry: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let date: String
    let headline: String
    let changes: [String]

    init(version: String, date: String, headline: String, changes: [String]) {
        self.id = version
        self.version = version
        self.date = date
        self.headline = headline
        self.changes = changes
    }
}

enum ReleaseHistoryCatalog {
    static let entries: [ReleaseHistoryEntry] = [
        ReleaseHistoryEntry(
            version: "1.4.7",
            date: "May 18, 2026",
            headline: "Network debugging and settings polish.",
            changes: [
                "Added the network debugging module.",
                "Added adjustable network traffic layout controls.",
                "Refined split-view behavior, updater state, and settings structure.",
            ]
        ),
        ReleaseHistoryEntry(
            version: "1.4.6",
            date: "May 18, 2026",
            headline: "Leaderboard sync, caching, and status monitoring.",
            changes: [
                "Added local leaderboard caching and sync support.",
                "Added leaderboard history sync and display.",
                "Added OpenAI and Codex service status monitoring.",
            ]
        ),
        ReleaseHistoryEntry(
            version: "1.4.5",
            date: "May 17, 2026",
            headline: "System monitor and richer leaderboard history.",
            changes: [
                "Added the system monitor feature.",
                "Added complete leaderboard history support.",
                "Refined leaderboard layout and component structure.",
            ]
        ),
        ReleaseHistoryEntry(
            version: "1.4.4",
            date: "May 17, 2026",
            headline: "App icon, status, and cost-estimation updates.",
            changes: [
                "Added new app icon assets and configuration.",
                "Added cost estimation mode and Claude status monitoring.",
                "Added long-context pricing support and improved activity analysis structure.",
            ]
        ),
        ReleaseHistoryEntry(
            version: "1.4.1 / 1.4.2",
            date: "May 17, 2026",
            headline: "CLI environment tools and provider switching.",
            changes: [
                "Added CLI environment detection and cleanup.",
                "Added API provider switching with configurable key storage.",
                "Rebuilt the activity page around the new main-window activity view.",
            ]
        ),
        ReleaseHistoryEntry(
            version: "1.4.0",
            date: "May 17, 2026",
            headline: "Terminal, Git stats, and release-readiness improvements.",
            changes: [
                "Added terminal support and Git language statistics.",
                "Added Git stats scope preferences and refreshed Git controls.",
                "Added the in-app update badge and cleaned up release pipeline dependencies.",
            ]
        ),
    ]
}
