import Foundation

struct TechnicalTermDictionary: Sendable {
    struct Entry: Hashable, Sendable {
        let canonical: String
        let kind: TranscriptTermKind
        let aliases: [String]
        let weight: Double
    }

    static let currentVersion = "technical-terms-v1"

    let entries: [Entry]
    let stopwords: Set<String>

    init(
        entries: [Entry] = TechnicalTermDictionary.defaultEntries,
        stopwords: Set<String> = TechnicalTermDictionary.defaultStopwords
    ) {
        self.entries = entries
        self.stopwords = stopwords
    }

    var dictionaryVersion: String { Self.currentVersion }

    var userWords: [String] {
        Array(Set(entries.flatMap { [$0.canonical] + $0.aliases })).sorted()
    }

    func canonicalize(_ raw: String) -> Entry? {
        let folded = Self.normalized(raw)
        return entries.first { entry in
            Self.normalized(entry.canonical) == folded
                || entry.aliases.contains { Self.normalized($0) == folded }
        }
    }

    func matches(in text: String) -> [Entry] {
        let foldedText = Self.normalizedSearchText(text)
        var out: [Entry] = []
        for entry in entries {
            let candidates = [entry.canonical] + entry.aliases
            if candidates.contains(where: { foldedText.contains(Self.normalizedSearchText($0)) }) {
                out.append(entry)
            }
        }
        return out
    }

    func isStopword(_ token: String) -> Bool {
        stopwords.contains(Self.normalized(token))
    }

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: "-")
    }

    static func normalizedSearchText(_ value: String) -> String {
        " " + normalized(value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ") + " "
    }

    private static let defaultEntries: [Entry] = [
        Entry(canonical: "Swift", kind: .language, aliases: ["swiftlang"], weight: 1.6),
        Entry(canonical: "SwiftUI", kind: .framework, aliases: ["swift ui"], weight: 2.0),
        Entry(canonical: "AppKit", kind: .framework, aliases: ["nsview", "nswindow"], weight: 1.8),
        Entry(canonical: "NaturalLanguage", kind: .framework, aliases: ["natural language", "nltagger", "nlembedding"], weight: 1.8),
        Entry(canonical: "Xcode", kind: .workflow, aliases: ["xcodebuild", "xcodegen"], weight: 1.8),
        Entry(canonical: "XcodeGen", kind: .workflow, aliases: ["project.yml"], weight: 1.8),
        Entry(canonical: "Sparkle", kind: .framework, aliases: ["appcast", "spustandardupdatercontroller"], weight: 1.8),
        Entry(canonical: "GitHub Actions", kind: .workflow, aliases: [".github/workflows", "release workflow"], weight: 1.8),
        Entry(canonical: "notarization", kind: .workflow, aliases: ["notarytool", "staple"], weight: 1.7),
        Entry(canonical: "code signing", kind: .workflow, aliases: ["codesign", "hardened runtime"], weight: 1.7),
        Entry(canonical: "Launch Services", kind: .api, aliases: ["lsuielement", "deriveddata"], weight: 1.7),
        Entry(canonical: "CloudKit", kind: .framework, aliases: ["icloud"], weight: 1.5),
        Entry(canonical: "Screen Time", kind: .api, aliases: ["full disk access"], weight: 1.5),
        Entry(canonical: "CppJieba", kind: .framework, aliases: ["jieba", "结巴", "中文分词"], weight: 2.0),
        Entry(canonical: "TF-IDF", kind: .api, aliases: ["tfidf", "term frequency", "document frequency"], weight: 2.0),
        Entry(canonical: "embedding", kind: .api, aliases: ["embeddings", "vector", "core ml"], weight: 1.8),
        Entry(canonical: "Sendable", kind: .api, aliases: ["swift concurrency"], weight: 1.7),
        Entry(canonical: "Observation", kind: .framework, aliases: ["@observable"], weight: 1.6),
        Entry(canonical: "JSONL", kind: .api, aliases: ["transcript", "rollout"], weight: 1.4),
    ]

    private static let defaultStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for", "from", "has",
        "have", "i", "if", "in", "is", "it", "its", "let", "not", "of", "on", "or", "our", "should",
        "that", "the", "their", "then", "there", "this", "to", "use", "var", "was", "we", "with", "you",
        "一个", "一些", "不会", "不是", "以及", "他们", "使用", "可以", "因为", "如果", "就是", "我们",
        "所以", "这个", "这些", "还是", "需要", "然后", "进行", "里面"
    ]
}
