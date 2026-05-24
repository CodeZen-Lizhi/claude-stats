import Foundation
import Observation

struct TechnicalTermDictionaryStats: Hashable, Sendable {
    var builtInTerms = 0
    var globalCustomTerms = 0
    var projectTerms = 0
    var disabledTerms = 0
}

@MainActor
@Observable
final class TechnicalTermDictionaryStore {
    private(set) var state = TechnicalTermDictionaryEditorState.empty
    private(set) var availableProjectPaths: [String] = []
    private(set) var revision = 0
    private(set) var errorMessage: String?

    var selectedProjectPath: String?

    @ObservationIgnored let repository: TechnicalTermDictionaryRepository

    init(repository: TechnicalTermDictionaryRepository = TechnicalTermDictionaryRepository()) {
        self.repository = repository
    }

    var stats: TechnicalTermDictionaryStats {
        let disabled = editableEntries.filter { !$0.enabled }.count
            + effectiveBuiltInEntries.filter { !$0.enabled }.count
        return TechnicalTermDictionaryStats(
            builtInTerms: state.builtIn.terms.count,
            globalCustomTerms: state.global.terms.count,
            projectTerms: state.project.terms.count,
            disabledTerms: disabled
        )
    }

    var rows: [TechnicalTermDictionaryRow] {
        let builtIn = effectiveBuiltInEntries.map {
            TechnicalTermDictionaryRow(source: .builtIn, entry: $0)
        }
        let global = state.global.terms.map {
            TechnicalTermDictionaryRow(source: .globalUser, entry: $0)
        }
        let project = state.project.terms.map {
            TechnicalTermDictionaryRow(source: .project, entry: $0)
        }
        return (builtIn + global + project).sorted { lhs, rhs in
            lhs.entry.canonical.localizedCaseInsensitiveCompare(rhs.entry.canonical) == .orderedAscending
        }
    }

    func filteredRows(
        scope: TechnicalTermEditScope,
        category: TechnicalTermCategory?,
        query: String
    ) -> [TechnicalTermDictionaryRow] {
        let scopeRows = rows.filter { row in
            switch scope {
            case .global:
                row.source != .project
            case .project:
                true
            }
        }
        let categoryRows = category.map { selected in
            scopeRows.filter { $0.entry.category == selected }
        } ?? scopeRows
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categoryRows }

        let needle = TermNormalizer.normalizedKey(trimmed)
        return categoryRows.filter { row in
            let entry = row.entry
            let haystack = ([
                entry.canonical,
                entry.kind.displayName,
                entry.category.rawValue,
                entry.category.displayName,
                row.source.displayName,
            ] + entry.aliases + entry.tags)
                .map(TermNormalizer.normalizedKey)
                .joined(separator: " ")
            return haystack.contains(needle)
        }
    }

    func load(sessions: [Session]) async {
        availableProjectPaths = await repository.availableProjectPaths(from: sessions)
        if selectedProjectPath == nil {
            selectedProjectPath = availableProjectPaths.first
        }
        await reloadEditorState()
    }

    func selectProjectPath(_ path: String?) async {
        selectedProjectPath = path
        await reloadEditorState()
    }

    func corpusSignature(for sessions: [Session]) async -> String {
        await repository.corpusSignature(for: sessions)
    }

    @discardableResult
    func saveEntry(
        _ entry: TechnicalTermEntry,
        originalCanonical: String?,
        scope: TechnicalTermEditScope
    ) async -> Bool {
        await performMutation {
            try await repository.saveEntry(
                entry,
                originalCanonical: originalCanonical,
                scope: scope,
                projectPath: selectedProjectPath
            )
        }
    }

    @discardableResult
    func deleteEntry(canonical: String, scope: TechnicalTermEditScope) async -> Bool {
        await performMutation {
            try await repository.deleteEntry(
                canonical: canonical,
                scope: scope,
                projectPath: selectedProjectPath
            )
        }
    }

    @discardableResult
    func disableBuiltIn(_ entry: TechnicalTermEntry, scope: TechnicalTermEditScope) async -> Bool {
        await performMutation {
            try await repository.disableBuiltIn(entry, scope: scope, projectPath: selectedProjectPath)
        }
    }

    func importTerms(from url: URL, scope: TechnicalTermEditScope) async -> TechnicalTermImportResult? {
        var result: TechnicalTermImportResult?
        let ok = await performMutation {
            result = try await repository.importTerms(
                from: url,
                scope: scope,
                projectPath: selectedProjectPath
            )
        }
        return ok ? result : nil
    }

    @discardableResult
    func exportTerms(to url: URL, scope: TechnicalTermEditScope) async -> Bool {
        await performMutation {
            try await repository.exportTerms(to: url, scope: scope, projectPath: selectedProjectPath)
        }
    }

    private func reloadEditorState() async {
        state = await repository.editorState(selectedProjectPath: selectedProjectPath)
    }

    @discardableResult
    private func performMutation(_ mutation: () async throws -> Void) async -> Bool {
        do {
            try await mutation()
            errorMessage = nil
            revision += 1
            await reloadEditorState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private var editableEntries: [TechnicalTermEntry] {
        state.global.terms + state.project.terms
    }

    private var effectiveBuiltInEntries: [TechnicalTermEntry] {
        let overrides = editableEntries.reduce(into: [String: TechnicalTermEntry]()) { result, entry in
            result[TermNormalizer.normalizedKey(entry.canonical)] = entry
        }
        return state.builtIn.terms.map { entry in
            guard let override = overrides[TermNormalizer.normalizedKey(entry.canonical)] else {
                return entry
            }
            var merged = entry
            merged.enabled = override.enabled
            merged.kind = override.kind
            merged.category = override.category
            merged.weight = override.weight
            merged.aliases = Array(Set(entry.aliases + override.aliases)).sorted()
            merged.tags = Array(Set(entry.tags + override.tags)).sorted()
            return merged
        }
    }
}
