import CryptoKit
import Foundation

enum TechnicalTermEditScope: String, CaseIterable, Sendable, Hashable, Identifiable {
    case global
    case project

    var id: String { rawValue }
    var title: String {
        switch self {
        case .global: "Global"
        case .project: "Project"
        }
    }
}

actor TechnicalTermDictionaryRepository {
    private let builtInURL: URL?
    private let globalURL: URL
    private var builtInCache: TechnicalTermDocument?
    private var globalCache: TechnicalTermDocument?
    private var projectCache: [String: TechnicalTermDocument] = [:]
    private var projectDictionaryURLCache: [String: [URL]] = [:]
    private var snapshotCache: [String: TechnicalTermDictionarySnapshot] = [:]

    init(
        builtInURL: URL? = nil,
        globalURL: URL? = nil
    ) {
        self.builtInURL = builtInURL ?? Self.defaultBuiltInURL()
        self.globalURL = globalURL ?? Self.defaultGlobalURL()
    }

    func snapshot(for session: Session) -> TechnicalTermDictionarySnapshot {
        let cacheKey = snapshotCacheKey(for: session.cwd)
        if let cached = snapshotCache[cacheKey] { return cached }

        let snapshot = Self.merge(documents(for: session.cwd))
        snapshotCache[cacheKey] = snapshot
        return snapshot
    }

    func corpusSignature(for sessions: [Session]) -> String {
        var digestsByCacheKey: [String: String] = [:]
        digestsByCacheKey.reserveCapacity(sessions.count)

        let values = sessions.map { session in
            let cacheKey = snapshotCacheKey(for: session.cwd)
            let digest: String
            if let cachedDigest = digestsByCacheKey[cacheKey] {
                digest = cachedDigest
            } else {
                let snapshot = snapshot(for: session)
                digestsByCacheKey[cacheKey] = snapshot.digest
                digest = snapshot.digest
            }
            return "\(session.id):\(digest)"
        }
        .sorted()
        .joined(separator: "|")
        return Self.sha256(values)
    }

    func editorState(selectedProjectPath: String?) -> TechnicalTermDictionaryEditorState {
        TechnicalTermDictionaryEditorState(
            builtIn: builtInDocument(),
            global: globalDocument(),
            project: selectedProjectPath.map { projectDocument(for: $0) } ?? TechnicalTermDocument(),
            selectedProjectPath: selectedProjectPath
        )
    }

    func availableProjectPaths(from sessions: [Session]) -> [String] {
        Array(Set(sessions.compactMap(\.cwd).filter { !$0.isEmpty }))
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    func saveEntry(_ entry: TechnicalTermEntry, originalCanonical: String?, scope: TechnicalTermEditScope, projectPath: String?) throws {
        switch scope {
        case .global:
            var document = globalDocument()
            upsert(entry, originalCanonical: originalCanonical, in: &document)
            try saveGlobalDocument(document)
        case .project:
            guard let projectPath else { throw TechnicalTermDictionaryError.missingProject }
            var document = projectDocument(for: projectPath)
            upsert(entry, originalCanonical: originalCanonical, in: &document)
            try saveProjectDocument(document, for: projectPath)
        }
    }

    func deleteEntry(canonical: String, scope: TechnicalTermEditScope, projectPath: String?) throws {
        switch scope {
        case .global:
            var document = globalDocument()
            remove(canonical, from: &document)
            try saveGlobalDocument(document)
        case .project:
            guard let projectPath else { throw TechnicalTermDictionaryError.missingProject }
            var document = projectDocument(for: projectPath)
            remove(canonical, from: &document)
            try saveProjectDocument(document, for: projectPath)
        }
    }

    func disableBuiltIn(_ entry: TechnicalTermEntry, scope: TechnicalTermEditScope, projectPath: String?) throws {
        var override = entry
        override.enabled = false
        try saveEntry(override, originalCanonical: entry.canonical, scope: scope, projectPath: projectPath)
    }

    func importTerms(from url: URL, scope: TechnicalTermEditScope, projectPath: String?) throws -> TechnicalTermImportResult {
        let parsed = try Self.parseImport(from: url)
        switch scope {
        case .global:
            var document = globalDocument()
            merge(parsed.document.terms, into: &document)
            try saveGlobalDocument(document)
        case .project:
            guard let projectPath else { throw TechnicalTermDictionaryError.missingProject }
            var document = projectDocument(for: projectPath)
            merge(parsed.document.terms, into: &document)
            try saveProjectDocument(document, for: projectPath)
        }
        return TechnicalTermImportResult(
            imported: parsed.document.terms.count,
            skipped: parsed.skipped,
            messages: parsed.messages
        )
    }

    func exportTerms(to url: URL, scope: TechnicalTermEditScope, projectPath: String?) throws {
        let document: TechnicalTermDocument
        switch scope {
        case .global:
            document = globalDocument()
        case .project:
            guard let projectPath else { throw TechnicalTermDictionaryError.missingProject }
            document = projectDocument(for: projectPath)
        }
        try Self.write(document, to: url)
    }

    private func documents(for cwd: String?) -> [TechnicalTermDocument] {
        var docs = [builtInDocument(), globalDocument()]
        docs += projectDocuments(for: cwd)
        return docs
    }

    private func builtInDocument() -> TechnicalTermDocument {
        if let builtInCache { return builtInCache }
        let document = builtInURL.flatMap { try? Self.readDocument(at: $0) } ?? TechnicalTermDocument(
            terms: TechnicalTermDictionary.fallbackEntries,
            stopwords: Array(TechnicalTermDictionary.fallbackStopwords)
        )
        builtInCache = document
        return document
    }

    private func globalDocument() -> TechnicalTermDocument {
        if let globalCache { return globalCache }
        let document = (try? Self.readDocument(at: globalURL)) ?? TechnicalTermDocument()
        globalCache = document
        return document
    }

    private func projectDocuments(for cwd: String?) -> [TechnicalTermDocument] {
        projectDictionaryURLs(for: cwd).compactMap { url in
            let key = url.standardizedFileURL.path
            if let cached = projectCache[key] { return cached }
            guard let document = try? Self.readDocument(at: url) else { return nil }
            projectCache[key] = document
            return document
        }
    }

    private func projectDocument(for projectPath: String) -> TechnicalTermDocument {
        let url = Self.projectDictionaryURL(for: projectPath)
        let key = url.standardizedFileURL.path
        if let cached = projectCache[key] { return cached }
        let document = (try? Self.readDocument(at: url)) ?? TechnicalTermDocument()
        projectCache[key] = document
        return document
    }

    private func saveGlobalDocument(_ document: TechnicalTermDocument) throws {
        try Self.write(document, to: globalURL)
        globalCache = document
        invalidateSnapshotCache()
    }

    private func saveProjectDocument(_ document: TechnicalTermDocument, for projectPath: String) throws {
        let url = Self.projectDictionaryURL(for: projectPath)
        try Self.write(document, to: url)
        projectCache[url.standardizedFileURL.path] = document
        projectDictionaryURLCache.removeAll()
        invalidateSnapshotCache()
    }

    private func projectDictionaryURLs(for cwd: String?) -> [URL] {
        guard let cwd, !cwd.isEmpty else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var current = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        let cacheKey = current.path
        if let cached = projectDictionaryURLCache[cacheKey] { return cached }

        var urls: [URL] = []
        while current.path.hasPrefix(home.path) {
            let candidate = current
                .appendingPathComponent(".claude-stats", isDirectory: true)
                .appendingPathComponent("terms.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                urls.append(candidate)
            }
            if current.path == home.path { break }
            current.deleteLastPathComponent()
        }
        let resolved = Array(urls.reversed())
        projectDictionaryURLCache[cacheKey] = resolved
        return resolved
    }

    private func snapshotCacheKey(for cwd: String?) -> String {
        projectDictionaryURLs(for: cwd)
            .map { $0.standardizedFileURL.path }
            .joined(separator: "\u{1f}")
    }

    private func invalidateSnapshotCache() {
        snapshotCache.removeAll()
    }

    private func upsert(_ entry: TechnicalTermEntry, originalCanonical: String?, in document: inout TechnicalTermDocument) {
        if let originalCanonical {
            remove(originalCanonical, from: &document)
        }
        merge([entry], into: &document)
    }

    private func merge(_ entries: [TechnicalTermEntry], into document: inout TechnicalTermDocument) {
        for entry in entries {
            upsertMerged(entry, in: &document)
        }
    }

    private func upsertMerged(_ entry: TechnicalTermEntry, in document: inout TechnicalTermDocument) {
        let key = TermNormalizer.normalizedKey(entry.canonical)
        if let index = document.terms.firstIndex(where: { TermNormalizer.normalizedKey($0.canonical) == key }) {
            var existing = document.terms[index]
            existing.canonical = entry.canonical
            existing.kind = entry.kind
            existing.category = entry.category
            existing.weight = entry.weight
            existing.enabled = entry.enabled
            existing.aliases = Array(Set(existing.aliases + entry.aliases)).sorted()
            existing.tags = Array(Set(existing.tags + entry.tags)).sorted()
            document.terms[index] = existing
        } else {
            document.terms.append(entry)
        }
        document.terms.sort { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
    }

    private func remove(_ canonical: String, from document: inout TechnicalTermDocument) {
        let key = TermNormalizer.normalizedKey(canonical)
        document.terms.removeAll { TermNormalizer.normalizedKey($0.canonical) == key }
    }

    private static func merge(_ documents: [TechnicalTermDocument]) -> TechnicalTermDictionarySnapshot {
        var merged: [String: TechnicalTermEntry] = [:]
        var stopwords = Set<String>()

        for document in documents {
            stopwords.formUnion(document.stopwords.map(TermNormalizer.normalizedKey))
            for entry in document.terms {
                let key = TermNormalizer.normalizedKey(entry.canonical)
                if var existing = merged[key] {
                    existing.canonical = entry.canonical
                    existing.kind = entry.kind
                    existing.category = entry.category
                    existing.weight = entry.weight
                    existing.enabled = entry.enabled
                    existing.aliases = Array(Set(existing.aliases + entry.aliases)).sorted()
                    existing.tags = Array(Set(existing.tags + entry.tags)).sorted()
                    merged[key] = existing
                } else {
                    merged[key] = entry
                }
            }
        }

        return TechnicalTermDictionarySnapshot.make(
            entries: Array(merged.values),
            stopwords: stopwords
        )
    }

    private static func readDocument(at url: URL) throws -> TechnicalTermDocument {
        let data = try Data(contentsOf: url)
        if let document = try? JSONDecoder().decode(TechnicalTermDocument.self, from: data) {
            return document
        }
        let entries = try JSONDecoder().decode([TechnicalTermEntry].self, from: data)
        return TechnicalTermDocument(terms: entries)
    }

    private static func write(_ document: TechnicalTermDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private static func parseImport(from url: URL) throws -> (document: TechnicalTermDocument, skipped: Int, messages: [String]) {
        switch url.pathExtension.lowercased() {
        case "json":
            return (try readDocument(at: url), 0, [])
        case "csv":
            return try parseCSVImport(from: url)
        default:
            return try parseTXTImport(from: url)
        }
    }

    private static func parseTXTImport(from url: URL) throws -> (TechnicalTermDocument, Int, [String]) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var entries: [TechnicalTermEntry] = []
        var skipped = 0
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                skipped += trimmed.isEmpty ? 0 : 1
                continue
            }
            entries.append(TechnicalTermEntry(canonical: trimmed, kind: .general, weight: 1.4))
        }
        return (TechnicalTermDocument(terms: entries), skipped, [])
    }

    private static func parseCSVImport(from url: URL) throws -> (TechnicalTermDocument, Int, [String]) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let rows = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !rows.isEmpty else { return (TechnicalTermDocument(), 0, []) }

        let headers = parseCSVLine(rows[0]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func value(_ name: String, in columns: [String]) -> String {
            guard let index = headers.firstIndex(of: name), index < columns.count else { return "" }
            return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var entries: [TechnicalTermEntry] = []
        var skipped = 0
        var messages: [String] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let columns = parseCSVLine(row)
            let canonical = value("canonical", in: columns)
            guard !canonical.isEmpty else {
                skipped += 1
                messages.append("Row \(offset + 2): missing canonical.")
                continue
            }
            let kind = TranscriptTermKind(rawValue: value("kind", in: columns)) ?? .general
            let category = TechnicalTermCategory.parse(value("category", in: columns)) ?? .general
            let aliases = splitList(value("aliases", in: columns))
            let tags = splitList(value("tags", in: columns))
            let weight = Double(value("weight", in: columns)) ?? 1.4
            let enabled = Bool(value("enabled", in: columns).lowercased()) ?? true
            entries.append(TechnicalTermEntry(
                canonical: canonical,
                kind: kind,
                category: category,
                aliases: aliases,
                weight: weight,
                enabled: enabled,
                tags: tags
            ))
        }
        return (TechnicalTermDocument(terms: entries), skipped, messages)
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            columns.append(current)
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        columns.append(current)
        return columns
    }

    private static func splitList(_ value: String) -> [String] {
        value
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func projectDictionaryURL(for projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".claude-stats", isDirectory: true)
            .appendingPathComponent("terms.json")
    }

    private static func defaultGlobalURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("com.claudestats.ClaudeStats", isDirectory: true)
            .appendingPathComponent("TranscriptAnalysis", isDirectory: true)
            .appendingPathComponent("user_terms.json")
    }

    private static func defaultBuiltInURL() -> URL? {
        Bundle.main.url(
            forResource: "technical_terms",
            withExtension: "json",
            subdirectory: "TranscriptAnalysis"
        ) ?? Bundle.main.url(forResource: "technical_terms", withExtension: "json")
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "dictionary-corpus-\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}

enum TechnicalTermDictionaryError: LocalizedError {
    case missingProject

    var errorDescription: String? {
        switch self {
        case .missingProject: "Select a project before editing project terms."
        }
    }
}
