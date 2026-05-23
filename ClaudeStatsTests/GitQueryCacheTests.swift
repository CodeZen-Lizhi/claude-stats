import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git query cache")
struct GitQueryCacheTests {
    @Test("Invalidating one repo does not cancel another repo's in-flight graph page")
    func invalidationIsRepoScoped() async throws {
        let cache = GitQueryCache(ttl: 60)
        let repoA = GitRepo(rootPath: "/repos/a", gitDirPath: "/repos/a/.git", commonDirPath: "/repos/a/.git")
        let repoB = GitRepo(rootPath: "/repos/b", gitDirPath: "/repos/b/.git", commonDirPath: "/repos/b/.git")
        let keyB = GitRepositoryService.graphPageCacheKey(for: repoB, offset: 0, limit: 200)
        let expected = GitGraphPage(
            repo: repoB,
            commits: [
                GraphCommit(
                    hash: String(repeating: "b", count: 40),
                    parentHashes: [],
                    refs: [],
                    author: "Ada",
                    authorEmail: "ada@example.com",
                    date: .now,
                    subject: "Initial"
                ),
            ],
            offset: 0,
            limit: 200,
            hasMore: false,
            workingTree: .clean
        )

        let task = Task {
            await cache.graphPage(key: keyB) {
                Thread.sleep(forTimeInterval: 0.15)
                return expected
            }
        }

        try await Task.sleep(for: .milliseconds(40))
        await cache.invalidate(repo: repoA)
        let loaded = await task.value

        #expect(loaded?.repo == repoB)
        #expect(loaded?.commits.first?.hash == expected.commits.first?.hash)
    }
}
