import CryptoKit
import Foundation

enum TechnicalTermSource: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case builtIn
    case globalUser
    case project

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn: "Built-in"
        case .globalUser: "Global"
        case .project: "Project"
        }
    }
}

enum TechnicalTermCategory: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case uiUX
    case architecture
    case frontend
    case backend
    case cloudDevOps
    case commandLine
    case testingQuality
    case security
    case dataAI
    case applePlatform
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uiUX: "UI / UX"
        case .architecture: "Architecture"
        case .frontend: "Frontend"
        case .backend: "Backend"
        case .cloudDevOps: "Cloud / DevOps"
        case .commandLine: "Command Line"
        case .testingQuality: "Testing / Quality"
        case .security: "Security"
        case .dataAI: "Data / AI"
        case .applePlatform: "Apple Platform"
        case .general: "General"
        }
    }

    static func parse(_ value: String) -> TechnicalTermCategory? {
        let normalized = TermNormalizer.normalizedKey(value)
        return allCases.first { category in
            normalized == TermNormalizer.normalizedKey(category.rawValue)
                || normalized == TermNormalizer.normalizedKey(category.displayName)
        }
    }
}

struct TechnicalTermEntry: Codable, Hashable, Identifiable, Sendable {
    var canonical: String
    var kind: TranscriptTermKind
    var category: TechnicalTermCategory
    var aliases: [String]
    var weight: Double
    var enabled: Bool
    var tags: [String]

    var id: String { TermNormalizer.normalizedKey(canonical) }

    init(
        canonical: String,
        kind: TranscriptTermKind,
        category: TechnicalTermCategory = .general,
        aliases: [String] = [],
        weight: Double = 1.4,
        enabled: Bool = true,
        tags: [String] = []
    ) {
        self.canonical = canonical
        self.kind = kind
        self.category = category
        self.aliases = aliases
        self.weight = weight
        self.enabled = enabled
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case canonical, kind, category, aliases, weight, enabled, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonical = try container.decode(String.self, forKey: .canonical)
        kind = try container.decodeIfPresent(TranscriptTermKind.self, forKey: .kind) ?? .general
        category = try container.decodeIfPresent(TechnicalTermCategory.self, forKey: .category) ?? .general
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1.4
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct TechnicalTermDocument: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var terms: [TechnicalTermEntry]
    var stopwords: [String]

    init(schemaVersion: Int = 1, terms: [TechnicalTermEntry] = [], stopwords: [String] = []) {
        self.schemaVersion = schemaVersion
        self.terms = terms
        self.stopwords = stopwords
    }
}

struct TechnicalTermDictionarySnapshot: Hashable, Sendable {
    let entries: [TechnicalTermEntry]
    let stopwords: Set<String>
    let digest: String

    var dictionary: TechnicalTermDictionary {
        TechnicalTermDictionary(entries: entries, stopwords: stopwords, dictionaryVersion: digest)
    }

    static let fallback = TechnicalTermDictionarySnapshot(
        entries: TechnicalTermDictionary.fallbackEntries,
        stopwords: TechnicalTermDictionary.fallbackStopwords,
        digest: Self.digest(entries: TechnicalTermDictionary.fallbackEntries, stopwords: TechnicalTermDictionary.fallbackStopwords)
    )

    static func make(entries: [TechnicalTermEntry], stopwords: Set<String>) -> TechnicalTermDictionarySnapshot {
        let enabledEntries = entries.filter(\.enabled)
        return TechnicalTermDictionarySnapshot(
            entries: enabledEntries,
            stopwords: stopwords,
            digest: digest(entries: enabledEntries, stopwords: stopwords)
        )
    }

    static func digest(entries: [TechnicalTermEntry], stopwords: Set<String>) -> String {
        let rows = entries
            .map { entry in
                let canonicalKey = TermNormalizer.normalizedKey(entry.canonical)
                let row = [
                    canonicalKey,
                    entry.kind.rawValue,
                    entry.category.rawValue,
                    String(format: "%.4f", entry.weight),
                    entry.aliases.map(TermNormalizer.normalizedKey).sorted().joined(separator: ","),
                    entry.tags.map(TermNormalizer.normalizedKey).sorted().joined(separator: ","),
                ].joined(separator: "\u{1f}")
                return (key: canonicalKey, row: row)
            }
            .sorted { $0.key < $1.key }
            .map(\.row)
        let stopwordRows = stopwords.map(TermNormalizer.normalizedKey).sorted()
        let payload = (rows + ["--stopwords--"] + stopwordRows).joined(separator: "\u{1e}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "dictionary-\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}

struct TechnicalTermMatch: Hashable, Sendable {
    let entry: TechnicalTermEntry
    let matchedText: String
    let isFuzzy: Bool

    var canonical: String { entry.canonical }
    var kind: TranscriptTermKind { entry.kind }
    var weight: Double { entry.weight }
}

struct TechnicalTermImportResult: Hashable, Sendable {
    let imported: Int
    let skipped: Int
    let messages: [String]

    var summary: String {
        if skipped == 0 {
            return "Imported \(imported) term\(imported == 1 ? "" : "s")."
        }
        return "Imported \(imported), skipped \(skipped)."
    }
}

struct TechnicalTermDictionaryEditorState: Hashable, Sendable {
    var builtIn: TechnicalTermDocument
    var global: TechnicalTermDocument
    var project: TechnicalTermDocument
    var selectedProjectPath: String?

    static let empty = TechnicalTermDictionaryEditorState(
        builtIn: TechnicalTermDocument(),
        global: TechnicalTermDocument(),
        project: TechnicalTermDocument(),
        selectedProjectPath: nil
    )
}

struct TechnicalTermDictionaryRow: Identifiable, Hashable, Sendable {
    let source: TechnicalTermSource
    let entry: TechnicalTermEntry

    var id: String { "\(source.rawValue)|\(TermNormalizer.normalizedKey(entry.canonical))" }
}
