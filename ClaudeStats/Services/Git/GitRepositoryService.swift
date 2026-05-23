import Foundation

struct GitRepositoryService: Sendable {
    static let shared = GitRepositoryService()

    private let analyzer: GitAnalyzer
    private let cache: GitQueryCache

    init(analyzer: GitAnalyzer = GitAnalyzer(), cache: GitQueryCache = .shared) {
        self.analyzer = analyzer
        self.cache = cache
    }

    func graphPage(for repo: GitRepo, offset: Int, limit: Int) async -> GitGraphPage? {
        let key = Self.graphPageCacheKey(for: repo, offset: offset, limit: limit)
        return await cache.graphPage(key: key) {
            analyzer.graphPage(for: repo, offset: offset, limit: limit)
        }
    }

    func commitDetail(for hash: String, in repo: GitRepo) async -> CommitDetail? {
        let key = "\(repo.cacheKey)|detail|\(hash)"
        return await cache.commitDetail(key: key) {
            analyzer.commitDetail(for: hash, in: repo)
        }
    }

    func fileDiff(for hash: String, path: String, in repo: GitRepo) async -> FileDiff? {
        let key = "\(repo.cacheKey)|diff|\(hash)|\(path)"
        return await cache.fileDiff(key: key) {
            analyzer.fileDiff(for: hash, path: path, in: repo)
        }
    }

    func fileChanges(for hash: String, in repo: GitRepo) async -> [CommitFileChange] {
        let key = "\(repo.cacheKey)|file-changes|\(hash)"
        return await cache.fileChanges(key: key) {
            analyzer.fileChanges(for: hash, in: repo)
        }
    }

    func minimapData(for repo: GitRepo, limit: Int, targetMaxBuckets: Int, selectedHash: String?) async -> GitGraphMinimapData? {
        let key = Self.minimapCacheKey(for: repo, limit: limit, targetMaxBuckets: targetMaxBuckets)
        let data = await cache.minimap(key: key) {
            let commits = analyzer.minimapCommits(for: repo, limit: limit)
            guard !commits.isEmpty else {
                let workingTree = analyzer.workingTreeSummary(for: repo)
                guard workingTree.isDirty else { return nil }
                return GitGraphMinimapData.build(
                    commits: [],
                    refsByHash: [:],
                    workingTree: workingTree,
                    selectedHash: nil,
                    targetMaxBuckets: targetMaxBuckets,
                    currentBranch: repo.currentBranch
                )
            }
            return GitGraphMinimapData.build(
                commits: commits,
                refsByHash: analyzer.refsByHash(for: repo),
                workingTree: analyzer.workingTreeSummary(for: repo),
                selectedHash: nil,
                targetMaxBuckets: targetMaxBuckets,
                currentBranch: repo.currentBranch
            )
        }
        return data?.selecting(hash: selectedHash)
    }

    static func minimapCacheKey(for repo: GitRepo, limit: Int, targetMaxBuckets: Int) -> String {
        "\(repo.worktreeKey)|minimap|\(limit)|\(max(targetMaxBuckets, 1))"
    }

    static func graphPageCacheKey(for repo: GitRepo, offset: Int, limit: Int) -> String {
        "\(repo.worktreeKey)|graph-page|\(offset)|\(limit)"
    }

    func invalidate(repo: GitRepo) async {
        await cache.invalidate(repo: repo)
    }
}
