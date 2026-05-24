import Foundation

struct TranscriptTFIDFAnalyzer: Sendable {
    func snapshot(
        provider: ProviderKind,
        sessions: [Session],
        sessionAnalyses: [TranscriptSessionAnalysis],
        engine: TranscriptAnalysisEngineInfo,
        dictionarySignature: String = TechnicalTermDictionarySnapshot.fallback.digest,
        runSummary: TranscriptAnalysisRunSummary = .empty,
        now: Date = .now
    ) -> TranscriptAnalysisSnapshot {
        let documentCount = max(sessionAnalyses.count, 1)
        var frequency: [TermKey: Int] = [:]
        var documentFrequency: [TermKey: Int] = [:]
        var roleCounts: [TermKey: TranscriptRoleCounts] = [:]
        var sourceCounts: [TermKey: TranscriptSourceCounts] = [:]
        var displayNames: [TermKey: String] = [:]
        var aliases: [TermKey: Set<String>] = [:]
        var examples: [TermKey: [TranscriptTermExample]] = [:]
        var averageWeight: [TermKey: Double] = [:]

        for analysis in sessionAnalyses {
            var seen: Set<TermKey> = []
            for term in analysis.terms {
                let key = TermKey(canonical: term.canonical, kind: term.kind)
                frequency[key, default: 0] += term.frequency
                seen.insert(key)
                displayNames[key] = displayNames[key] ?? term.displayName
                averageWeight[key, default: 0] += term.weight
                aliases[key, default: []].insert(term.displayName)
                roleCounts[key, default: TranscriptRoleCounts()].merge(term.roleCounts)
                sourceCounts[key, default: TranscriptSourceCounts()].merge(term.sourceCounts)
                if let example = term.example {
                    var existing = examples[key, default: []]
                    if existing.count < 3 {
                        existing.append(example)
                    }
                    examples[key] = existing
                }
            }
            for key in seen {
                documentFrequency[key, default: 0] += 1
            }
        }

        let terms = frequency.map { key, count in
            let df = max(documentFrequency[key] ?? 1, 1)
            let idf = log((Double(documentCount) + 1.0) / (Double(df) + 1.0)) + 1.0
            let kindBoost = boost(for: key.kind)
            let weight = (averageWeight[key] ?? 1.0) / Double(max(df, 1))
            return TranscriptTermStats(
                canonical: key.canonical,
                displayName: displayNames[key] ?? key.canonical,
                kind: key.kind,
                aliases: Array(aliases[key] ?? []).filter { $0 != displayNames[key] }.sorted(),
                frequency: count,
                documentFrequency: df,
                tfidf: Double(count) * idf * kindBoost * max(weight, 0.8),
                roleCounts: roleCounts[key] ?? TranscriptRoleCounts(),
                sourceCounts: sourceCounts[key] ?? TranscriptSourceCounts(),
                examples: examples[key] ?? []
            )
        }
        .sorted {
            if $0.tfidf != $1.tfidf { return $0.tfidf > $1.tfidf }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return TranscriptAnalysisSnapshot(
            provider: provider,
            generatedAt: now,
            sessionCount: sessions.count,
            analyzedSessionCount: sessionAnalyses.count,
            terms: terms,
            sessionAnalyses: sessionAnalyses,
            engine: engine,
            dictionarySignature: dictionarySignature,
            runSummary: runSummary
        )
    }

    private func boost(for kind: TranscriptTermKind) -> Double {
        switch kind {
        case .filePath, .command, .error: 1.45
        case .framework, .api, .typeName, .configKey: 1.25
        case .language, .workflow: 1.15
        case .function: 1.2
        case .general: 1.0
        }
    }
}

private struct TermKey: Hashable {
    let canonical: String
    let kind: TranscriptTermKind
}

private extension TranscriptRoleCounts {
    mutating func merge(_ other: TranscriptRoleCounts) {
        user += other.user
        assistant += other.assistant
        tool += other.tool
        system += other.system
    }
}

private extension TranscriptSourceCounts {
    mutating func merge(_ other: TranscriptSourceCounts) {
        dictionary += other.dictionary
        naturalLanguage += other.naturalLanguage
        jieba += other.jieba
        code += other.code
        path += other.path
        command += other.command
        error += other.error
        project += other.project
    }
}
