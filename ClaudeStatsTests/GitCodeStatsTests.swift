import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git code statistics")
struct GitCodeStatsTests {
    @Test("syntax mapping matches filename, extension, shebang and XML declaration")
    func syntaxMapping() throws {
        let catalog = GitSyntaxCatalog(definitions: Self.syntaxDefinitions)

        #expect(catalog.definition(forPath: "Makefile", contentPrefix: "")?.name == "Makefile")
        #expect(catalog.definition(forPath: "Sources/App.SWIFT", contentPrefix: "")?.name == "Swift")
        #expect(catalog.definition(forPath: "script", contentPrefix: "#!/usr/bin/env python3\nprint('hi')")?.name == "Python")
        #expect(catalog.definition(forPath: "document", contentPrefix: "<?xml version=\"1.0\"?>")?.name == "XML")
    }

    @Test("filename mapping takes precedence over extension")
    func syntaxMappingPrecedence() throws {
        let definitions = [
            "ByName": GitSyntaxDefinition(
                kind: .code,
                fileMap: GitSyntaxFileMap(extensions: [], filenames: ["Build.swift"], interpreters: []),
                comment: nil,
                stringDelimiters: []
            ),
            "ByExtension": GitSyntaxDefinition(
                kind: .code,
                fileMap: GitSyntaxFileMap(extensions: ["swift"], filenames: [], interpreters: []),
                comment: nil,
                stringDelimiters: []
            ),
        ]
        let catalog = GitSyntaxCatalog(definitions: definitions)
        #expect(catalog.definition(forPath: "Build.swift", contentPrefix: "")?.name == "ByName")
    }

    @Test("line counter ignores comment markers inside Swift strings and counts nested blocks")
    func swiftLineCounting() throws {
        let syntax = try #require(Self.syntaxDefinitions["Swift"])
        let source = """
        let url = "https://example.com//path"
        // one comment
        let value = 1 /* trailing */
        /*
         outer
         /* inner */
        */

        """
        let count = GitCodeLineCounter.count(source, syntax: syntax)
        #expect(count.totalLines == 7)
        #expect(count.codeLines == 2)
        #expect(count.commentLines == 6)
        #expect(count.blankLines == 0)
    }

    @Test("YAML hash inside quotes is code, trailing hash is a comment")
    func yamlLineCounting() throws {
        let syntax = try #require(Self.syntaxDefinitions["YAML"])
        let source = """
        url: "https://example.com/#anchor" # trailing
        # full comment

        """
        let count = GitCodeLineCounter.count(source, syntax: syntax)
        #expect(count.totalLines == 2)
        #expect(count.codeLines == 1)
        #expect(count.commentLines == 2)
        #expect(count.blankLines == 0)
    }

    @Test("JSON line comments follow CotEditor metadata and CRLF counts by logical line")
    func jsonLineCounting() throws {
        let syntax = try #require(Self.syntaxDefinitions["JSON"])
        let source = "{\r\n  \"url\": \"https://example.com//path\",\r\n  // comment\r\n  \"ok\": true\r\n}\r\n"
        let count = GitCodeLineCounter.count(source, syntax: syntax)
        #expect(count.totalLines == 5)
        #expect(count.codeLines == 4)
        #expect(count.commentLines == 1)
        #expect(count.blankLines == 0)
    }

    @Test("tracked repo stats exclude ignored, untracked and binary files", .enabled(if: GitAnalyzer().isAvailable))
    func realRepoCodeStats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitcodestats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try run(["init", "-q"], in: dir)
        try run(["config", "user.email", "me@example.com"], in: dir)
        try run(["config", "user.name", "Me"], in: dir)
        try run(["config", "commit.gpgsign", "false"], in: dir)

        try "*.ignored\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env python3
        print("hi")
        """.write(to: dir.appendingPathComponent("tool"), atomically: true, encoding: .utf8)
        try """
        let value = "not // comment"
        // comment
        """.write(to: dir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: dir.appendingPathComponent("logo.png"))
        try "ignored\n".write(to: dir.appendingPathComponent("skip.ignored"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: dir.appendingPathComponent("Loose.swift"), atomically: true, encoding: .utf8)

        try run(["add", ".gitignore", "tool", "App.swift", "logo.png"], in: dir)
        try run(["commit", "-q", "-m", "Initial"], in: dir)

        let repo = GitRepo(rootPath: dir.path)
        let analyzer = GitAnalyzer()
        let files = analyzer.trackedFiles(in: repo)
        #expect(files.contains("App.swift"))
        #expect(files.contains("tool"))
        #expect(!files.contains("Loose.swift"))
        #expect(!files.contains("skip.ignored"))

        let stats = analyzer.codeStats(for: repo)
        #expect(stats.languageRows.contains { $0.language == "Swift" })
        #expect(stats.languageRows.contains { $0.language == "Python" })
        #expect(stats.skippedBinaryFileCount == 1)
        #expect(stats.totalLines >= 4)

        let contributors = analyzer.contributorStats(for: repo)
        #expect(contributors.first?.email == "me@example.com")
        #expect(contributors.first?.commitCount == 1)

        let codeContributors = analyzer.codeContributionStats(for: repo)
        #expect(codeContributors.first?.email == "me@example.com")
        #expect((codeContributors.first?.lineCount ?? 0) >= 4)
        #expect(codeContributors.first?.share == 1)
    }

    private static let syntaxDefinitions: [String: GitSyntaxDefinition] = [
        "Makefile": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: [], filenames: ["Makefile"], interpreters: ["make"]),
            comment: nil,
            stringDelimiters: []
        ),
        "Python": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: ["py"], filenames: [], interpreters: ["python3"]),
            comment: GitSyntaxComment(
                inlines: [.init(begin: "#", leadingOnly: false)],
                blocks: []
            ),
            stringDelimiters: [
                .init(begin: "\"", end: "\"", isMultiline: false, escapeCharacter: "\\"),
                .init(begin: "'", end: "'", isMultiline: false, escapeCharacter: "\\"),
            ]
        ),
        "Swift": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: ["swift"], filenames: [], interpreters: ["swift"]),
            comment: GitSyntaxComment(
                inlines: [.init(begin: "//", leadingOnly: false)],
                blocks: [.init(begin: "/*", end: "*/", isNestable: true)]
            ),
            stringDelimiters: [
                .init(begin: "\"", end: "\"", isMultiline: false, escapeCharacter: "\\"),
                .init(begin: "\"\"\"", end: "\"\"\"", isMultiline: true, escapeCharacter: "\\"),
            ]
        ),
        "XML": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: ["xml"], filenames: [], interpreters: []),
            comment: GitSyntaxComment(
                inlines: [],
                blocks: [.init(begin: "<!--", end: "-->", isNestable: false)]
            ),
            stringDelimiters: [.init(begin: "\"", end: "\"", isMultiline: false, escapeCharacter: nil)]
        ),
        "YAML": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: ["yml", "yaml"], filenames: [], interpreters: []),
            comment: GitSyntaxComment(
                inlines: [.init(begin: "#", leadingOnly: false)],
                blocks: []
            ),
            stringDelimiters: [
                .init(begin: "\"", end: "\"", isMultiline: true, escapeCharacter: "\\"),
                .init(begin: "'", end: "'", isMultiline: true, escapeCharacter: "'"),
            ]
        ),
        "JSON": GitSyntaxDefinition(
            kind: .code,
            fileMap: GitSyntaxFileMap(extensions: ["json"], filenames: [], interpreters: []),
            comment: GitSyntaxComment(
                inlines: [.init(begin: "//", leadingOnly: false)],
                blocks: [.init(begin: "/*", end: "*/", isNestable: false)]
            ),
            stringDelimiters: [.init(begin: "\"", end: "\"", isMultiline: false, escapeCharacter: "\\")]
        ),
    ]

    @discardableResult
    private func run(_ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: GitAnalyzer.gitPath)
        p.arguments = ["-C", dir.path] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
