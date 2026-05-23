import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git repo stats cache")
struct GitRepoStatsCacheTests {
    @Test("base and ownership stats read and write independently")
    func readWriteBaseAndOwnership() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = GitRepoStatsCache(directory: directory)
        let key = cache.key(
            repoRoot: "/repos/app",
            scope: .head,
            headHash: String(repeating: "a", count: 40),
            historySignature: "refs-a",
            runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a")
        )
        let base = GitRepoInspectorBaseStats(
            code: GitRepoCodeStats.unavailable(scope: .head, totalFiles: 3, warning: "missing"),
            contributors: [GitContributorStat(name: "Ada", email: "ada@example.com", commitCount: 2, share: 1)]
        )
        let ownership = GitRepoCodeOwnershipStats(
            codeContributors: [GitCodeContributionStat(name: "Ada", email: "ada@example.com", lineCount: 9, share: 1)]
        )

        cache.writeBase(base, for: key)
        cache.writeOwnership(ownership, for: key)

        #expect(cache.readBase(for: key) == base)
        #expect(cache.readOwnership(for: key) == ownership)
    }

    @Test("cache key changes with head, runtime and scope")
    func keyChangesWithInputs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = GitRepoStatsCache(directory: directory)

        let base = cache.key(repoRoot: "/repos/app", scope: .head, headHash: "a", historySignature: "refs-a", runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a"))
        let otherHead = cache.key(repoRoot: "/repos/app", scope: .head, headHash: "b", historySignature: "refs-a", runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a"))
        let otherRefs = cache.key(repoRoot: "/repos/app", scope: .head, headHash: "a", historySignature: "refs-b", runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a"))
        let otherRuntime = cache.key(repoRoot: "/repos/app", scope: .head, headHash: "a", historySignature: "refs-a", runtimeSignature: GitStatsRuntimeSignature(value: "runtime-b"))
        let otherScope = cache.key(repoRoot: "/repos/app", scope: .workingTree, headHash: "a", historySignature: "refs-a", runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a"))

        #expect(base.digest != otherHead.digest)
        #expect(base.digest != otherRefs.digest)
        #expect(base.digest != otherRuntime.digest)
        #expect(base.digest != otherScope.digest)
    }

    @Test("schema mismatch returns nil")
    func schemaMismatchReturnsNil() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldCache = GitRepoStatsCache(directory: directory, schemaVersion: 0)
        let currentCache = GitRepoStatsCache(directory: directory, schemaVersion: 1)
        let oldKey = oldCache.key(
            repoRoot: "/repos/app",
            scope: .head,
            headHash: "a",
            historySignature: "refs-a",
            runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a")
        )
        let base = GitRepoInspectorBaseStats(
            code: GitRepoCodeStats.unavailable(scope: .head, totalFiles: 1, warning: "old"),
            contributors: []
        )

        oldCache.writeBase(base, for: oldKey)

        #expect(currentCache.readBase(for: oldKey) == nil)
    }

    @Test("v2 empty payload is not read by current v3 cache")
    func v2EmptyPayloadIsNotCurrent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let v2Cache = GitRepoStatsCache(directory: directory, schemaVersion: 2)
        let currentCache = GitRepoStatsCache(directory: directory)
        let v2Key = v2Cache.key(
            repoRoot: "/repos/app",
            scope: .head,
            headHash: "a",
            historySignature: "refs-a",
            runtimeSignature: GitStatsRuntimeSignature(value: "runtime-a")
        )
        v2Cache.writeBase(.empty, for: v2Key)

        #expect(currentCache.readBase(for: v2Key) == nil)
    }

    @Test("contributor command failure returns warning and does not persist base cache", .enabled(if: GitAnalyzer().isAvailable))
    func contributorFailureDoesNotPersistBaseCache() throws {
        let repoDirectory = try temporaryDirectory()
        let cacheDirectory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repoDirectory)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }

        try run(["init", "-q", "-b", "main"], in: repoDirectory)
        try run(["config", "user.email", "me@example.com"], in: repoDirectory)
        try run(["config", "user.name", "Me"], in: repoDirectory)
        try run(["config", "commit.gpgsign", "false"], in: repoDirectory)
        try "hello\n".write(to: repoDirectory.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try run(["add", "readme.md"], in: repoDirectory)
        try run(["commit", "-q", "-m", "Initial"], in: repoDirectory)

        let service = GitRepoStatsService(
            analyzer: GitAnalyzer(runner: GitCommandRunner(executablePath: "/bin/false")),
            cache: GitRepoStatsCache(directory: cacheDirectory),
            runtimeSignature: GitStatsRuntimeSignature(value: "test-runtime"),
            ownershipAnalyzer: GitCodeOwnershipAnalyzer(maxConcurrentBlameJobs: 1),
            runner: GitCommandRunner()
        )
        let stats = service.baseStats(for: GitRepo(rootPath: repoDirectory.path), scope: .head)

        #expect(stats.contributors.isEmpty)
        #expect(stats.contributorsWarning != nil)
        #expect(try cachedFileCount(in: cacheDirectory) == 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("git-stats-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cachedFileCount(in directory: URL) throws -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

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
