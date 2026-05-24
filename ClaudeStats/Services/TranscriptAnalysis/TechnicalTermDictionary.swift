import Foundation

struct TechnicalTermDictionary: Sendable {
    static let currentVersion = "technical-terms-v2"

    let entries: [TechnicalTermEntry]
    let stopwords: Set<String>
    let dictionaryVersion: String

    init(
        entries: [TechnicalTermEntry] = TechnicalTermDictionary.fallbackEntries,
        stopwords: Set<String> = TechnicalTermDictionary.fallbackStopwords,
        dictionaryVersion: String = TechnicalTermDictionary.currentVersion
    ) {
        self.entries = entries.filter(\.enabled)
        self.stopwords = stopwords
        self.dictionaryVersion = dictionaryVersion
    }

    var userWords: [String] {
        Array(Set(entries.flatMap { [$0.canonical] + $0.aliases })).sorted()
    }

    func canonicalize(_ raw: String) -> TechnicalTermEntry? {
        let folded = Self.normalized(raw)
        let candidates = entries.flatMap { entry in
            ([entry.canonical] + entry.aliases).map { (entry: entry, key: Self.normalized($0)) }
        }
        if let exact = candidates.first(where: { $0.key == folded })?.entry {
            return exact
        }

        let rawTokens = TermNormalizer.tokens(in: raw)
        guard rawTokens.count >= 2 else { return nil }
        let fuzzyMatches = candidates.filter { candidate in
            let candidateTokens = candidate.key.split(separator: " ").map(String.init)
            return TermNormalizer.phraseMatches(candidate: candidateTokens, text: rawTokens, allowsFuzzy: true)
        }
        let unique = Dictionary(grouping: fuzzyMatches, by: { TermNormalizer.normalizedKey($0.entry.canonical) })
        return unique.count == 1 ? fuzzyMatches.first?.entry : nil
    }

    func matches(in text: String) -> [TechnicalTermMatch] {
        let textTokens = TermNormalizer.tokens(in: text)
        guard !textTokens.isEmpty else { return [] }

        var matches: [TechnicalTermMatch] = []
        var emitted: Set<String> = []
        for entry in entries {
            let candidates = Set(([entry.canonical] + entry.aliases).map(Self.normalized).filter { !$0.isEmpty })
            for candidate in candidates {
                let candidateTokens = candidate.split(separator: " ").map(String.init)
                guard !candidateTokens.isEmpty, candidateTokens.count <= textTokens.count else { continue }
                for start in 0...(textTokens.count - candidateTokens.count) {
                    let end = start + candidateTokens.count
                    let slice = Array(textTokens[start..<end])
                    let exact = slice == candidateTokens
                    let fuzzy = !exact && TermNormalizer.phraseMatches(
                        candidate: candidateTokens,
                        text: slice,
                        allowsFuzzy: true
                    )
                    guard exact || fuzzy else { continue }
                    let key = "\(TermNormalizer.normalizedKey(entry.canonical))|\(start)|\(end)"
                    guard emitted.insert(key).inserted else { continue }
                    matches.append(TechnicalTermMatch(
                        entry: entry,
                        matchedText: slice.joined(separator: " "),
                        isFuzzy: fuzzy
                    ))
                }
            }
        }
        return matches
    }

    func isStopword(_ token: String) -> Bool {
        stopwords.contains(Self.normalized(token))
    }

    static func normalized(_ value: String) -> String {
        TermNormalizer.normalizedKey(value)
    }

    static func normalizedSearchText(_ value: String) -> String {
        TermNormalizer.normalizedSearchText(value)
    }

    static let fallbackEntries: [TechnicalTermEntry] = [
        TechnicalTermEntry(canonical: "Swift", kind: .language, aliases: ["swiftlang"], weight: 1.6),
        TechnicalTermEntry(canonical: "SwiftUI", kind: .framework, aliases: ["swift ui"], weight: 2.0),
        TechnicalTermEntry(canonical: "AppKit", kind: .framework, aliases: ["nsview", "nswindow"], weight: 1.8),
        TechnicalTermEntry(canonical: "NaturalLanguage", kind: .framework, aliases: ["natural language", "nltagger", "nlembedding"], weight: 1.8),
        TechnicalTermEntry(canonical: "Xcode", kind: .workflow, aliases: ["xcodebuild", "xcodegen"], weight: 1.8),
        TechnicalTermEntry(canonical: "XcodeGen", kind: .workflow, aliases: ["project.yml"], weight: 1.8),
        TechnicalTermEntry(canonical: "Sparkle", kind: .framework, aliases: ["appcast", "spustandardupdatercontroller"], weight: 1.8),
        TechnicalTermEntry(canonical: "GitHub Actions", kind: .workflow, aliases: ["github actions", ".github/workflows", "release workflow"], weight: 1.8),
        TechnicalTermEntry(canonical: "notarization", kind: .workflow, aliases: ["notarytool", "staple"], weight: 1.7),
        TechnicalTermEntry(canonical: "code signing", kind: .workflow, aliases: ["codesign", "hardened runtime"], weight: 1.7),
        TechnicalTermEntry(canonical: "Launch Services", kind: .api, aliases: ["lsuielement", "deriveddata"], weight: 1.7),
        TechnicalTermEntry(canonical: "MenuBarExtra", kind: .api, aliases: ["menubar extra", "menu bar extra", "Menu Bar Extra", "menu-bar-extra", "NSStatusItem", "菜单栏额外项"], weight: 2.0),
        TechnicalTermEntry(canonical: "main window", kind: .api, aliases: ["mainWindow", "MainWindow", "main windows", "主窗口", "主窗体", "main 窗口"], weight: 1.9),
        TechnicalTermEntry(canonical: "z-index", kind: .api, aliases: ["zIndex", "z index", "z_index", "层级", "叠放层级", "层叠顺序"], weight: 1.8),
        TechnicalTermEntry(canonical: "WindowGroup", kind: .api, aliases: ["window group", "窗口组"], weight: 1.8),
        TechnicalTermEntry(canonical: "CloudKit", kind: .framework, aliases: ["icloud"], weight: 1.5),
        TechnicalTermEntry(canonical: "Screen Time", kind: .api, aliases: ["full disk access"], weight: 1.5),
        TechnicalTermEntry(canonical: "CppJieba", kind: .framework, aliases: ["jieba", "结巴", "中文分词"], weight: 2.0),
        TechnicalTermEntry(canonical: "TF-IDF", kind: .api, aliases: ["tfidf", "term frequency", "document frequency"], weight: 2.0),
        TechnicalTermEntry(canonical: "embedding", kind: .api, aliases: ["embeddings", "vector", "core ml"], weight: 1.8),
        TechnicalTermEntry(canonical: "Sendable", kind: .api, aliases: ["swift concurrency"], weight: 1.7),
        TechnicalTermEntry(canonical: "Observation", kind: .framework, aliases: ["@observable"], weight: 1.6),
        TechnicalTermEntry(canonical: "JSONL", kind: .api, aliases: ["transcript", "rollout"], weight: 1.4),
    ]

    static let fallbackStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for", "from", "has",
        "have", "i", "if", "in", "is", "it", "its", "let", "not", "of", "on", "or", "our", "should",
        "that", "the", "their", "then", "there", "this", "to", "use", "var", "was", "we", "with", "you",
        "一个", "一些", "不会", "不是", "以及", "他们", "使用", "可以", "因为", "如果", "就是", "我们",
        "所以", "这个", "这些", "还是", "需要", "然后", "进行", "里面"
    ].map(TermNormalizer.normalizedKey).reduce(into: Set<String>()) { $0.insert($1) }
}
