import Foundation

enum SessionsDestination: Hashable, Sendable {
    case overview
    case session(String)

    static let overviewRawValue = "overview"
    private static let sessionPrefix = "session:"

    init(rawValue: String) {
        if rawValue.hasPrefix(Self.sessionPrefix) {
            let id = String(rawValue.dropFirst(Self.sessionPrefix.count))
            self = id.isEmpty ? .overview : .session(id)
        } else {
            self = .overview
        }
    }

    var rawValue: String {
        switch self {
        case .overview:
            Self.overviewRawValue
        case .session(let id):
            Self.sessionPrefix + id
        }
    }
}
