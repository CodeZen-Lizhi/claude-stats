import Foundation
import Observation

/// UI state for the Sessions screen: a search query and a sort order. The
/// derived list is computed against a ``SessionStore`` passed in by the view.
@MainActor
@Observable
final class SessionListViewModel {
    var searchText: String = ""
    var sortOrder: SortOrder = .recent

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent, tokens, cost
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .recent: "Recent"
            case .tokens: "Tokens"
            case .cost: "Cost"
            }
        }
    }

    func sessions(from store: SessionStore) -> [Session] {
        var result = store.sessions

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { session in
                session.projectDisplayName.lowercased().contains(query)
                    || (session.stats?.title.lowercased().contains(query) ?? false)
                    || (session.cwd?.lowercased().contains(query) ?? false)
            }
        }

        switch sortOrder {
        case .recent:
            result.sort { ($0.stats?.lastActivity ?? $0.lastModified) > ($1.stats?.lastActivity ?? $1.lastModified) }
        case .tokens:
            result.sort { ($0.stats?.totalTokens ?? 0) > ($1.stats?.totalTokens ?? 0) }
        case .cost:
            result.sort { ($0.stats?.totalCost ?? 0) > ($1.stats?.totalCost ?? 0) }
        }
        return result
    }
}
