import Foundation

struct TechnicalTermDictionary: Sendable {
    static let currentVersion = "technical-terms-v2"

    let entries: [TechnicalTermEntry]
    let stopwords: Set<String>
    let dictionaryVersion: String
    private let exactLookup: [String: TechnicalTermEntry]
    private let userWordsCache: [String]
    private let jiebaUserWordsCache: [String]
    private let candidatesByFirstToken: [String: [TechnicalTermCandidate]]
    private let candidateFirstTokensByLength: [Int: [String]]

    init(
        entries: [TechnicalTermEntry] = TechnicalTermDictionary.fallbackEntries,
        stopwords: Set<String> = TechnicalTermDictionary.fallbackStopwords,
        dictionaryVersion: String = TechnicalTermDictionary.currentVersion
    ) {
        let enabledEntries = entries.filter(\.enabled)
        self.entries = enabledEntries
        self.stopwords = stopwords
        self.dictionaryVersion = dictionaryVersion
        var exactLookup: [String: TechnicalTermEntry] = [:]
        var candidatesByFirstToken: [String: [TechnicalTermCandidate]] = [:]
        var candidateFirstTokensByLength: [Int: Set<String>] = [:]
        let words = Set(enabledEntries.flatMap { [$0.canonical] + $0.aliases })
        for entry in enabledEntries {
            let keys = Set(([entry.canonical] + entry.aliases).map(Self.normalized).filter { !$0.isEmpty })
            for key in keys {
                exactLookup[key] = exactLookup[key] ?? entry
                let candidate = TechnicalTermCandidate(
                    entry: entry,
                    tokens: key.split(separator: " ").map(String.init)
                )
                if let firstToken = candidate.tokens.first {
                    candidatesByFirstToken[firstToken, default: []].append(candidate)
                    candidateFirstTokensByLength[firstToken.count, default: []].insert(firstToken)
                }
            }
        }
        self.exactLookup = exactLookup
        self.userWordsCache = words.sorted()
        self.jiebaUserWordsCache = words.filter(Self.containsCJK).sorted()
        self.candidatesByFirstToken = candidatesByFirstToken
        self.candidateFirstTokensByLength = candidateFirstTokensByLength.mapValues { $0.sorted() }
    }

    var userWords: [String] {
        userWordsCache
    }

    var jiebaUserWords: [String] {
        jiebaUserWordsCache
    }

    func canonicalize(_ raw: String) -> TechnicalTermEntry? {
        let folded = Self.normalized(raw)
        if let exact = exactLookup[folded] {
            return exact
        }

        let rawTokens = TermNormalizer.tokens(in: raw)
        guard rawTokens.count >= 2 else { return nil }
        let fuzzyMatches = candidates(matchingFirstTokenOf: rawTokens).filter { candidate in
            Self.phraseMatches(candidate: candidate.tokens, textTokens: rawTokens, start: 0, allowsFuzzy: true).matched
        }
        let unique = Dictionary(grouping: fuzzyMatches, by: { TermNormalizer.normalizedKey($0.entry.canonical) })
        return unique.count == 1 ? fuzzyMatches.first?.entry : nil
    }

    func matches(in text: String) -> [TechnicalTermMatch] {
        let textTokens = TermNormalizer.tokens(in: text)
        guard !textTokens.isEmpty else { return [] }

        var matches: [TechnicalTermMatch] = []
        var emitted: Set<String> = []
        for start in textTokens.indices {
            let candidates = candidates(matchingFirstTokenOf: textTokens[start])
            for candidate in candidates {
                guard !candidate.tokens.isEmpty, start + candidate.tokens.count <= textTokens.count else { continue }
                let end = start + candidate.tokens.count
                let result = Self.phraseMatches(
                    candidate: candidate.tokens,
                    textTokens: textTokens,
                    start: start,
                    allowsFuzzy: true
                )
                guard result.matched else { continue }
                let key = "\(TermNormalizer.normalizedKey(candidate.entry.canonical))|\(start)|\(end)"
                guard emitted.insert(key).inserted else { continue }
                matches.append(TechnicalTermMatch(
                    entry: candidate.entry,
                    matchedText: textTokens[start..<end].joined(separator: " "),
                    isFuzzy: result.fuzzy
                ))
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

    private func candidates(matchingFirstTokenOf tokens: [String]) -> [TechnicalTermCandidate] {
        guard let firstToken = tokens.first else { return [] }
        return candidates(matchingFirstTokenOf: firstToken)
    }

    private func candidates(matchingFirstTokenOf firstToken: String) -> [TechnicalTermCandidate] {
        var matches = candidatesByFirstToken[firstToken] ?? []
        guard firstToken.count >= 3 else { return matches }

        for length in (firstToken.count - 1)...(firstToken.count + 1) {
            guard let firstTokens = candidateFirstTokensByLength[length] else { continue }
            for candidateFirstToken in firstTokens where candidateFirstToken != firstToken {
                guard max(candidateFirstToken.count, firstToken.count) >= 4,
                      TermNormalizer.isDistanceAtMostOne(candidateFirstToken, firstToken),
                      let candidates = candidatesByFirstToken[candidateFirstToken] else {
                    continue
                }
                matches += candidates
            }
        }
        return matches
    }

    private static func phraseMatches(
        candidate: [String],
        textTokens: [String],
        start: Int,
        allowsFuzzy: Bool
    ) -> (matched: Bool, fuzzy: Bool) {
        guard !candidate.isEmpty, start + candidate.count <= textTokens.count else { return (false, false) }

        var editCount = 0
        for (offset, lhs) in candidate.enumerated() {
            let rhs = textTokens[start + offset]
            if lhs == rhs { continue }
            guard allowsFuzzy, candidate.count >= 2 else { return (false, false) }
            guard lhs.count >= 4 || rhs.count >= 4 else { return (false, false) }
            guard TermNormalizer.isDistanceAtMostOne(lhs, rhs) else { return (false, false) }
            editCount += 1
            guard editCount <= 1 else { return (false, false) }
        }

        return editCount == 0 ? (true, false) : (true, true)
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }
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

private struct TechnicalTermCandidate: Sendable {
    let entry: TechnicalTermEntry
    let tokens: [String]
}
