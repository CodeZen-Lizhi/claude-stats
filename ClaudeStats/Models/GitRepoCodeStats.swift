import Foundation

struct GitRepoCodeStats: Sendable, Equatable {
    struct LanguageRow: Identifiable, Sendable, Equatable {
        let language: String
        let fileCount: Int
        let totalLines: Int
        let codeLines: Int
        let commentLines: Int
        let blankLines: Int

        var id: String { language }
        var codeAndCommentLines: Int { codeLines + commentLines }
    }

    let totalFiles: Int
    let textFileCount: Int
    let skippedBinaryFileCount: Int
    let totalLines: Int
    let codeLines: Int
    let commentLines: Int
    let blankLines: Int
    let languageRows: [LanguageRow]

    static let empty = GitRepoCodeStats(
        totalFiles: 0,
        textFileCount: 0,
        skippedBinaryFileCount: 0,
        totalLines: 0,
        codeLines: 0,
        commentLines: 0,
        blankLines: 0,
        languageRows: []
    )

    var codeAndCommentLines: Int { codeLines + commentLines }
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
