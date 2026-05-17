import Foundation

enum GitStatsScope: String, CaseIterable, Identifiable, Sendable {
    case head
    case workingTree

    var id: String { rawValue }

    var label: String {
        switch self {
        case .head: return "HEAD"
        case .workingTree: return "Working Tree"
        }
    }
}

enum GitLanguageStatsEngine: String, Sendable {
    case linguist
    case linguistLargeTree
    case sccFallback
    case unavailable

    var label: String {
        switch self {
        case .linguist: return "GitHub Linguist"
        case .linguistLargeTree: return "GitHub Linguist (large repo)"
        case .sccFallback: return "scc fallback"
        case .unavailable: return "Unavailable"
        }
    }
}

struct GitRepoCodeStats: Sendable, Equatable {
    struct LanguageRow: Identifiable, Sendable, Equatable {
        let language: String
        let fileCount: Int
        let sizeBytes: Int
        let byteShare: Double
        let totalLines: Int
        let sourceLines: Int

        var id: String { language }
    }

    let engine: GitLanguageStatsEngine
    let scope: GitStatsScope
    let warning: String?
    let totalFiles: Int
    let analyzedFiles: Int
    let skippedFiles: Int
    let totalBytes: Int
    let totalLines: Int
    let sourceLines: Int
    let codeFilePaths: [String]
    let languageRows: [LanguageRow]

    static let empty = GitRepoCodeStats(
        engine: .unavailable,
        scope: .head,
        warning: nil,
        totalFiles: 0,
        analyzedFiles: 0,
        skippedFiles: 0,
        totalBytes: 0,
        totalLines: 0,
        sourceLines: 0,
        codeFilePaths: [],
        languageRows: []
    )

    static func unavailable(scope: GitStatsScope, totalFiles: Int, warning: String) -> GitRepoCodeStats {
        GitRepoCodeStats(
            engine: .unavailable,
            scope: scope,
            warning: warning,
            totalFiles: totalFiles,
            analyzedFiles: 0,
            skippedFiles: totalFiles,
            totalBytes: 0,
            totalLines: 0,
            sourceLines: 0,
            codeFilePaths: [],
            languageRows: []
        )
    }
}

struct GitContributorStat: Identifiable, Sendable, Equatable {
    let name: String
    let email: String
    let commitCount: Int
    let share: Double

    var id: String { "\(name)|\(email)" }
    var displayName: String {
        email.isEmpty ? name : "\(name) <\(email)>"
    }
}

struct GitCodeContributionStat: Identifiable, Sendable, Equatable {
    let name: String
    let email: String
    let lineCount: Int
    let share: Double

    var id: String { "\(name)|\(email)" }
    var displayName: String {
        email.isEmpty ? name : "\(name) <\(email)>"
    }
}

struct GitRepoInspectorStats: Sendable, Equatable {
    let code: GitRepoCodeStats
    let codeContributors: [GitCodeContributionStat]
    let contributors: [GitContributorStat]

    static let empty = GitRepoInspectorStats(code: .empty, codeContributors: [], contributors: [])
}
