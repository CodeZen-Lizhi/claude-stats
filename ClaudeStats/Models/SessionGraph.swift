import Foundation

/// Provider-owned relationship metadata used to fold child agent sessions into
/// the parent session view without changing aggregate ledger accounting.
struct SessionAgentInfo: Sendable, Hashable, Codable {
    var threadSource: String?
    var parentSessionID: String?
    var nickname: String?
    var role: String?
    var path: String?

    var displayTitle: String {
        let parts = [nickname, role].reduce(into: [String]()) { result, value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            result.append(trimmed)
        }
        return parts.isEmpty ? "Subagent" : parts.joined(separator: " / ")
    }
}

/// A parent-session task window. Child sessions without an explicit parent can
/// only be attached when their activity fits one of these windows.
struct SessionTaskInterval: Sendable, Hashable, Codable {
    let id: String
    let start: Date
    let end: Date
}
