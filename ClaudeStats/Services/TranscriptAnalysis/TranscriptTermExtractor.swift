import Foundation
import NaturalLanguage

struct TranscriptTermExtractor: Sendable {
    private let tokenizer: JiebaTokenizer
    private let defaultDictionary: TechnicalTermDictionary
    private let regexCatalog: TranscriptRegexCatalog

    init(
        tokenizer: JiebaTokenizer = JiebaTokenizer(),
        dictionary: TechnicalTermDictionary = TechnicalTermDictionary()
    ) {
        self.tokenizer = tokenizer
        self.defaultDictionary = dictionary
        self.regexCatalog = .shared
    }

    var engineInfo: TranscriptAnalysisEngineInfo {
        get async {
            await engineInfo(dictionaryVersion: defaultDictionary.dictionaryVersion)
        }
    }

    func engineInfo(dictionaryVersion: String) async -> TranscriptAnalysisEngineInfo {
        let jiebaAvailable = await tokenizer.isAvailable
        return TranscriptAnalysisEngineInfo(
            tokenizerID: jiebaAvailable ? "cppjieba-natural-language-v1" : "fallback-natural-language-v1",
            dictionaryVersion: dictionaryVersion,
            displayName: jiebaAvailable ? "Jieba + NaturalLanguage" : "NaturalLanguage fallback",
            embeddingStatus: UnconfiguredEmbeddingEngine().status
        )
    }

    func extract(
        session: Session,
        messages: [SessionTranscriptMessage],
        dictionary: TechnicalTermDictionary? = nil
    ) async -> TranscriptSessionAnalysis {
        let dictionary = dictionary ?? defaultDictionary
        let projectTerms = projectTerms(for: session, dictionary: dictionary)
        await tokenizer.insertUserWords(dictionary.jiebaUserWords + projectTerms.filter(containsCJK))

        var accumulator = SessionTermAccumulator(
            sessionID: session.id,
            sessionTitle: session.stats?.title ?? session.externalID,
            projectName: session.projectDisplayName
        )

        for message in messages {
            let excerpt = excerpt(from: message.text)
            extractDictionaryTerms(from: message, session: session, dictionary: dictionary, excerpt: excerpt, into: &accumulator)
            extractStructuredTerms(from: message, session: session, dictionary: dictionary, excerpt: excerpt, into: &accumulator)
            await extractLanguageTerms(from: message, session: session, dictionary: dictionary, excerpt: excerpt, into: &accumulator)
        }

        for term in projectTerms.prefix(12) {
            accumulator.add(
                canonical: term,
                displayName: term,
                kind: inferIdentifierKind(term, dictionary: dictionary),
                role: .system,
                source: .project,
                weight: 1.2,
                excerpt: session.cwd ?? session.projectDisplayName,
                timestamp: nil
            )
        }

        return accumulator.build()
    }

    private func extractDictionaryTerms(
        from message: SessionTranscriptMessage,
        session: Session,
        dictionary: TechnicalTermDictionary,
        excerpt: String,
        into accumulator: inout SessionTermAccumulator
    ) {
        for entry in dictionary.matches(in: message.text) {
            accumulator.add(
                canonical: entry.canonical,
                displayName: entry.canonical,
                kind: entry.kind,
                role: message.role,
                source: .dictionary,
                weight: entry.weight,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }
    }

    private func extractStructuredTerms(
        from message: SessionTranscriptMessage,
        session: Session,
        dictionary: TechnicalTermDictionary,
        excerpt: String,
        into accumulator: inout SessionTermAccumulator
    ) {
        let text = message.text

        addMatches(regexCatalog.codeSpan, in: text, group: 1) { raw in
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldKeepStructuredTerm(cleaned, dictionary: dictionary) else { return }
            accumulator.add(
                canonical: canonicalIdentifier(cleaned, dictionary: dictionary),
                displayName: cleaned,
                kind: inferStructuredKind(cleaned, dictionary: dictionary),
                role: message.role,
                source: .code,
                weight: 2.2,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }

        addMatches(
            regexCatalog.filePath,
            in: text
        ) { raw in
            accumulator.add(
                canonical: raw,
                displayName: raw,
                kind: .filePath,
                role: message.role,
                source: .path,
                weight: 2.3,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }

        addMatches(
            regexCatalog.command,
            in: text
        ) { raw in
            accumulator.add(
                canonical: raw,
                displayName: raw,
                kind: .command,
                role: message.role,
                source: .command,
                weight: 2.0,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }

        addMatches(regexCatalog.configKey, in: text) { raw in
            accumulator.add(
                canonical: raw,
                displayName: raw,
                kind: .configKey,
                role: message.role,
                source: .code,
                weight: 1.8,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }

        addMatches(regexCatalog.identifier, in: text) { raw in
            guard shouldKeepIdentifier(raw, dictionary: dictionary) else { return }
            accumulator.add(
                canonical: canonicalIdentifier(raw, dictionary: dictionary),
                displayName: raw,
                kind: inferIdentifierKind(raw, dictionary: dictionary),
                role: message.role,
                source: .code,
                weight: 1.7,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }

        for phrase in errorPhrases(in: text) {
            accumulator.add(
                canonical: phrase,
                displayName: phrase,
                kind: .error,
                role: message.role,
                source: .error,
                weight: 2.2,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }
    }

    private func extractLanguageTerms(
        from message: SessionTranscriptMessage,
        session: Session,
        dictionary: TechnicalTermDictionary,
        excerpt: String,
        into accumulator: inout SessionTermAccumulator
    ) async {
        let text = regexCatalog.removingCodeSpans(from: message.text)
        for cjkSpan in cjkSpans(in: text) {
            let precise = await tokenizer.cut(cjkSpan)
            let search = await tokenizer.cut(cjkSpan, forSearch: true)
            for token in Array(Set(precise + search)) {
                let cleaned = cleanedLanguageToken(token)
                guard shouldKeepLanguageToken(cleaned, dictionary: dictionary) else { continue }
                accumulator.add(
                    canonical: TechnicalTermDictionary.normalized(cleaned),
                    displayName: cleaned,
                    kind: dictionary.canonicalize(cleaned)?.kind ?? .general,
                    role: message.role,
                    source: .jieba,
                    weight: dictionary.canonicalize(cleaned)?.weight ?? 1.0,
                    excerpt: excerpt,
                    timestamp: message.timestamp
                )
            }
        }

        for token in englishTerms(in: naturalLanguageText(from: text), dictionary: dictionary) {
            accumulator.add(
                canonical: TechnicalTermDictionary.normalized(token),
                displayName: token,
                kind: dictionary.canonicalize(token)?.kind ?? .general,
                role: message.role,
                source: .naturalLanguage,
                weight: dictionary.canonicalize(token)?.weight ?? 1.0,
                excerpt: excerpt,
                timestamp: message.timestamp
            )
        }
    }

    private func englishTerms(in text: String, dictionary: TechnicalTermDictionary) -> [String] {
        guard shouldRunNaturalLanguage(on: text) else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var out: [String] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: options) { tag, tokenRange in
            let raw = String(text[tokenRange])
            let lemma = tag?.rawValue ?? raw
            let cleaned = cleanedLanguageToken(lemma)
            if shouldKeepLanguageToken(cleaned, dictionary: dictionary) {
                out.append(cleaned)
            }
            return true
        }

        let words = out
        if words.count >= 2 {
            for index in 0..<(words.count - 1) {
                let phrase = "\(words[index]) \(words[index + 1])"
                if dictionary.canonicalize(phrase) != nil {
                    out.append(phrase)
                }
            }
        }
        return out
    }

    private func projectTerms(for session: Session, dictionary: TechnicalTermDictionary) -> [String] {
        var terms: Set<String> = []
        if let cwd = session.cwd {
            let url = URL(fileURLWithPath: cwd)
            terms.insert(url.lastPathComponent)
            for component in url.pathComponents.suffix(3) where component.count > 2 {
                terms.insert(component)
            }
        }
        terms.insert(session.projectDisplayName)
        terms.insert(session.projectDirectoryName)
        return Array(terms).filter { shouldKeepIdentifier($0, dictionary: dictionary) || containsCJK($0) }
    }

    private func addMatches(_ regex: NSRegularExpression, in text: String, group: Int = 0, handle: (String) -> Void) {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range(at: group), in: text) else { continue }
            handle(String(text[range]))
        }
    }

    private func errorPhrases(in text: String) -> [String] {
        let lower = text.lowercased()
        let catalog = [
            "build failed", "test failed", "compile error", "linker error", "crash",
            "exception", "warning", "permission denied", "not found", "timeout",
            "signing failed", "notarization failed", "launch services conflict"
        ]
        return catalog.filter { lower.contains($0) }
    }

    private func excerpt(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 160 else { return cleaned }
        return String(cleaned.prefix(157)) + "..."
    }

    private func cleanedLanguageToken(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
    }

    private func shouldKeepLanguageToken(_ token: String, dictionary: TechnicalTermDictionary) -> Bool {
        guard token.count >= 2, token.count <= 48 else { return false }
        if dictionary.isStopword(token) { return false }
        if token.allSatisfy(\.isNumber) { return false }
        return true
    }

    private func shouldKeepStructuredTerm(_ term: String, dictionary: TechnicalTermDictionary) -> Bool {
        term.count >= 2 && term.count <= 140 && !dictionary.isStopword(term)
    }

    private func shouldKeepIdentifier(_ value: String, dictionary: TechnicalTermDictionary) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3, cleaned.count <= 80 else { return false }
        if dictionary.isStopword(cleaned) { return false }
        return cleaned.contains { $0.isLetter }
    }

    private func canonicalIdentifier(_ value: String, dictionary: TechnicalTermDictionary) -> String {
        if let entry = dictionary.canonicalize(value) { return entry.canonical }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferStructuredKind(_ value: String, dictionary: TechnicalTermDictionary) -> TranscriptTermKind {
        if value.contains("/") || value.contains(".") { return .filePath }
        if value.contains(" ") { return .command }
        return inferIdentifierKind(value, dictionary: dictionary)
    }

    private func inferIdentifierKind(_ value: String, dictionary: TechnicalTermDictionary) -> TranscriptTermKind {
        if let entry = dictionary.canonicalize(value) { return entry.kind }
        if value.hasSuffix("View") || value.hasSuffix("Store") || value.hasSuffix("Service")
            || value.hasSuffix("Model") || value.hasSuffix("Controller") || value.hasSuffix("Parser") {
            return .typeName
        }
        if value.hasSuffix("()") { return .function }
        if value.contains("-") || value.contains("_") { return .workflow }
        return .api
    }

    private func naturalLanguageText(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .filter { !isCodeHeavyLine(String($0)) }
            .joined(separator: " ")
    }

    private func shouldRunNaturalLanguage(on text: String) -> Bool {
        guard text.contains(where: \.isLetter) else { return false }
        if text.count > 16_000 { return false }
        let punctuationCount = text.filter { "{}[]<>:=,\"".contains($0) }.count
        return Double(punctuationCount) / Double(max(text.count, 1)) < 0.22
    }

    private func isCodeHeavyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 24 else { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("//") { return true }
        if trimmed.contains(#"\"#) && trimmed.contains(":") { return true }
        let symbols = trimmed.filter { "{}[]<>:=;".contains($0) }.count
        return Double(symbols) / Double(max(trimmed.count, 1)) > 0.18
    }

    private func cjkSpans(in text: String) -> [String] {
        var spans: [String] = []
        var current = ""
        var hasCJK = false
        for scalar in text.unicodeScalars {
            let character = String(scalar)
            if isCJK(scalar) {
                current.append(character)
                hasCJK = true
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) {
                if hasCJK, !current.isEmpty {
                    spans.append(current)
                }
                current = ""
                hasCJK = false
            } else if hasCJK {
                current.append(character)
            }
        }
        if hasCJK, !current.isEmpty {
            spans.append(current)
        }
        return spans
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJK)
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
            || (0xF900...0xFAFF).contains(Int(scalar.value))
    }
}

private final class TranscriptRegexCatalog: @unchecked Sendable {
    static let shared = TranscriptRegexCatalog()

    let codeSpan = try! NSRegularExpression(pattern: #"`([^`\n]{2,120})`"#)
    let filePath = try! NSRegularExpression(pattern: #"\b[A-Za-z0-9_./+\-]+?\.(?:swift|yml|yaml|json|plist|sh|md|mm|m|h|hpp|cpp|xcstrings|xml)\b"#)
    let command = try! NSRegularExpression(pattern: #"\b(?:bash|git|xcodebuild|swift|npm|pnpm|bun|uv|python3?|codesign|notarytool|curl|rg|sed)\b(?:\s+[A-Za-z0-9_./:=+@%\-]+){0,5}"#)
    let configKey = try! NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9_]{2,}\b"#)
    let identifier = try! NSRegularExpression(pattern: #"\b(?:[A-Z][A-Za-z0-9]{3,}|[a-z]+(?:[A-Z][a-z0-9]+)+|[a-z0-9]+(?:[-_][a-z0-9]+)+)\b"#)

    func removingCodeSpans(from text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return codeSpan.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }
}

private struct SessionTermAccumulator {
    let sessionID: String
    let sessionTitle: String
    let projectName: String
    private var values: [String: MutableTerm] = [:]

    init(sessionID: String, sessionTitle: String, projectName: String) {
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.projectName = projectName
    }

    mutating func add(
        canonical: String,
        displayName: String,
        kind: TranscriptTermKind,
        role: SessionTranscriptMessage.Role,
        source: TranscriptTermSource,
        weight: Double,
        excerpt: String,
        timestamp: Date?
    ) {
        let normalized = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let key = "\(kind.rawValue)|\(TechnicalTermDictionary.normalized(normalized))"
        var term = values[key] ?? MutableTerm(
            canonical: normalized,
            displayName: displayName,
            kind: kind,
            weight: weight,
            roleCounts: TranscriptRoleCounts(),
            sourceCounts: TranscriptSourceCounts(),
            example: nil,
            aliases: []
        )
        term.frequency += 1
        term.weight = max(term.weight, weight)
        term.roleCounts.add(role)
        term.sourceCounts.add(source)
        if !term.aliases.contains(displayName), displayName != term.displayName {
            term.aliases.append(displayName)
        }
        if term.example == nil, !excerpt.isEmpty {
            term.example = TranscriptTermExample(
                id: "\(sessionID)-\(key)",
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                projectName: projectName,
                role: role,
                excerpt: excerpt,
                timestamp: timestamp
            )
        }
        values[key] = term
    }

    func build() -> TranscriptSessionAnalysis {
        let terms = values.values.map { value in
            TranscriptSessionTerm(
                canonical: value.canonical,
                displayName: value.displayName,
                kind: value.kind,
                frequency: value.frequency,
                weight: value.weight,
                roleCounts: value.roleCounts,
                sourceCounts: value.sourceCounts,
                example: value.example
            )
        }
        .sorted { $0.weightedFrequency > $1.weightedFrequency }

        return TranscriptSessionAnalysis(
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            projectName: projectName,
            terms: terms
        )
    }

    private struct MutableTerm {
        var canonical: String
        var displayName: String
        var kind: TranscriptTermKind
        var frequency = 0
        var weight: Double
        var roleCounts: TranscriptRoleCounts
        var sourceCounts: TranscriptSourceCounts
        var example: TranscriptTermExample?
        var aliases: [String]
    }
}
