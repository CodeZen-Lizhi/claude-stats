import Foundation

enum ProviderConfigFileKind: String, Codable, CaseIterable, Sendable, Hashable {
    case json
    case markdown
    case toml
    case text

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .markdown: "Markdown"
        case .toml: "TOML"
        case .text: "Text"
        }
    }
}
