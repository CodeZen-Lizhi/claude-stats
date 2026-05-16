import Foundation

struct GitCodeStatsAnalyzer: Sendable {
    private static let maxTextFileBytes = 2_000_000
    private static let binaryExtensions: Set<String> = [
        "a", "app", "bin", "bmp", "car", "class", "dmg", "doc", "docx", "dylib", "eot",
        "gif", "gz", "icns", "ico", "jar", "jpeg", "jpg", "mov", "mp3", "mp4", "otf",
        "pdf", "png", "so", "tiff", "ttf", "webp", "woff", "woff2", "xcarchive", "zip"
    ]

    private let catalog: GitSyntaxCatalog

    init(catalog: GitSyntaxCatalog = .bundled()) {
        self.catalog = catalog
    }

    func stats(repoRoot: String, trackedFiles: [String]) -> GitRepoCodeStats {
        var accumulators: [String: LanguageAccumulator] = [:]
        var textFileCount = 0
        var skippedBinaryFileCount = 0

        for path in trackedFiles {
            guard let text = supportedTextFile(repoRoot: repoRoot, path: path) else {
                skippedBinaryFileCount += 1
                continue
            }

            guard let match = catalog.definition(forPath: path, contentPrefix: String(text.prefix(4096))) else {
                continue
            }

            textFileCount += 1
            let count = GitCodeLineCounter.count(text, syntax: match.definition)
            accumulators[match.name, default: LanguageAccumulator()].add(count)
        }

        let rows = accumulators.map { language, acc in
            GitRepoCodeStats.LanguageRow(
                language: language,
                fileCount: acc.fileCount,
                totalLines: acc.totalLines,
                codeLines: acc.codeLines,
                commentLines: acc.commentLines,
                blankLines: acc.blankLines
            )
        }
        .sorted {
            if $0.codeAndCommentLines != $1.codeAndCommentLines {
                return $0.codeAndCommentLines > $1.codeAndCommentLines
            }
            return $0.language.localizedStandardCompare($1.language) == .orderedAscending
        }

        return GitRepoCodeStats(
            totalFiles: trackedFiles.count,
            textFileCount: textFileCount,
            skippedBinaryFileCount: skippedBinaryFileCount,
            totalLines: rows.reduce(0) { $0 + $1.totalLines },
            codeLines: rows.reduce(0) { $0 + $1.codeLines },
            commentLines: rows.reduce(0) { $0 + $1.commentLines },
            blankLines: rows.reduce(0) { $0 + $1.blankLines },
            languageRows: rows
        )
    }

    func recognizedTextFiles(repoRoot: String, trackedFiles: [String]) -> [String] {
        trackedFiles.compactMap { path in
            guard let text = supportedTextFile(repoRoot: repoRoot, path: path),
                  catalog.definition(forPath: path, contentPrefix: String(text.prefix(4096))) != nil else {
                return nil
            }
            return path
        }
    }

    private func supportedTextFile(repoRoot: String, path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if Self.binaryExtensions.contains(ext) {
            return nil
        }

        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= Self.maxTextFileBytes,
              !Self.looksBinary(data),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private static func looksBinary(_ data: Data) -> Bool {
        data.prefix(4096).contains(0)
    }

    private struct LanguageAccumulator: Sendable {
        var fileCount = 0
        var totalLines = 0
        var codeLines = 0
        var commentLines = 0
        var blankLines = 0

        mutating func add(_ count: GitCodeLineCounter.Count) {
            fileCount += 1
            totalLines += count.totalLines
            codeLines += count.codeLines
            commentLines += count.commentLines
            blankLines += count.blankLines
        }
    }
}

enum GitCodeLineCounter {
    struct Count: Sendable, Equatable {
        let totalLines: Int
        let codeLines: Int
        let commentLines: Int
        let blankLines: Int
    }

    private struct StringState {
        let delimiter: GitSyntaxStringDelimiter
    }

    private struct BlockState {
        let delimiter: GitSyntaxComment.Block
        var depth: Int
    }

    static func count(_ source: String, syntax: GitSyntaxDefinition) -> Count {
        let lines = source.gitStatLines()
        guard !lines.isEmpty else {
            return Count(totalLines: 0, codeLines: 0, commentLines: 0, blankLines: 0)
        }

        let strings = syntax.stringDelimiters
            .filter { !$0.begin.isEmpty && !$0.end.isEmpty }
            .sorted { $0.begin.count > $1.begin.count }
        let inlines = syntax.comment?.inlines
            .filter { !$0.begin.isEmpty }
            .sorted { $0.begin.count > $1.begin.count } ?? []
        let blocks = syntax.comment?.blocks
            .filter { !$0.begin.isEmpty && !$0.end.isEmpty }
            .sorted { $0.begin.count > $1.begin.count } ?? []

        var codeLines = 0
        var commentLines = 0
        var blankLines = 0
        var stringState: StringState?
        var blockState: BlockState?

        for line in lines {
            let result = classify(
                line,
                strings: strings,
                inlines: inlines,
                blocks: blocks,
                stringState: &stringState,
                blockState: &blockState
            )

            if result.isBlank {
                blankLines += 1
            } else {
                if result.hasCode { codeLines += 1 }
                if result.hasComment { commentLines += 1 }
            }
        }

        return Count(
            totalLines: lines.count,
            codeLines: codeLines,
            commentLines: commentLines,
            blankLines: blankLines
        )
    }

    private static func classify(
        _ line: String,
        strings: [GitSyntaxStringDelimiter],
        inlines: [GitSyntaxComment.Inline],
        blocks: [GitSyntaxComment.Block],
        stringState: inout StringState?,
        blockState: inout BlockState?
    ) -> (hasCode: Bool, hasComment: Bool, isBlank: Bool) {
        var index = line.startIndex
        var hasCode = false
        var hasComment = false

        while index < line.endIndex {
            if var state = blockState {
                hasComment = true
                if state.delimiter.isNestable, line[index...].hasPrefix(state.delimiter.begin) {
                    state.depth += 1
                    blockState = state
                    index = line.index(index, offsetBy: state.delimiter.begin.count)
                    continue
                }
                if line[index...].hasPrefix(state.delimiter.end) {
                    state.depth -= 1
                    index = line.index(index, offsetBy: state.delimiter.end.count)
                    blockState = state.depth > 0 ? state : nil
                    continue
                }
                index = line.index(after: index)
                continue
            }

            if let state = stringState {
                hasCode = true
                if let escape = state.delimiter.escapeCharacter,
                   !escape.isEmpty,
                   line[index...].hasPrefix(escape) {
                    index = line.index(index, offsetBy: escape.count)
                    if index < line.endIndex {
                        index = line.index(after: index)
                    }
                    continue
                }
                if line[index...].hasPrefix(state.delimiter.end) {
                    index = line.index(index, offsetBy: state.delimiter.end.count)
                    stringState = nil
                    continue
                }
                index = line.index(after: index)
                continue
            }

            if line[index].isWhitespace {
                index = line.index(after: index)
                continue
            }

            if let inline = inlines.first(where: { line[index...].hasPrefix($0.begin) }),
               !inline.leadingOnly || !hasCode {
                hasComment = true
                break
            }

            if let block = blocks.first(where: { line[index...].hasPrefix($0.begin) }) {
                hasComment = true
                blockState = BlockState(delimiter: block, depth: 1)
                index = line.index(index, offsetBy: block.begin.count)
                continue
            }

            if let delimiter = strings.first(where: { line[index...].hasPrefix($0.begin) }) {
                hasCode = true
                index = line.index(index, offsetBy: delimiter.begin.count)
                stringState = StringState(delimiter: delimiter)
                continue
            }

            hasCode = true
            index = line.index(after: index)
        }

        if let state = stringState, !state.delimiter.isMultiline {
            stringState = nil
        }

        return (hasCode, hasComment, !hasCode && !hasComment)
    }
}

private extension String {
    func gitStatLines() -> [String] {
        guard !isEmpty else { return [] }
        var lines: [String] = []
        let nsString = self as NSString
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            lines.append(nsString.substring(with: range))
        }
        return lines
    }
}
