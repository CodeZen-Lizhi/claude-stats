import CryptoKit
import Foundation

struct GitRepoStatsService: Sendable {
    private let analyzer: GitAnalyzer
    private let cache: GitRepoStatsCache
    private let runtimeSignature: GitStatsRuntimeSignature
    private let ownershipAnalyzer: GitCodeOwnershipAnalyzer
    private let runner: GitCommandRunner

    init(
        analyzer: GitAnalyzer = GitAnalyzer(),
        cache: GitRepoStatsCache = GitRepoStatsCache(),
        runtimeSignature: GitStatsRuntimeSignature = .current(),
        ownershipAnalyzer: GitCodeOwnershipAnalyzer = GitCodeOwnershipAnalyzer(),
        runner: GitCommandRunner = GitCommandRunner()
    ) {
        self.analyzer = analyzer
        self.cache = cache
        self.runtimeSignature = runtimeSignature
        self.ownershipAnalyzer = ownershipAnalyzer
        self.runner = runner
    }

    func baseStats(for repo: GitRepo, scope: GitStatsScope) -> GitRepoInspectorBaseStats {
        let startedAt = Date()
        let key = cacheKey(for: repo, scope: scope)
        if let key, let cached = cache.readBase(for: key) {
            Log.git.info("Git base stats cache hit for \(repo.displayName, privacy: .public)")
            return cached
        }

        if key != nil {
            Log.git.info("Git base stats cache miss for \(repo.displayName, privacy: .public)")
        }

        let trackedFiles = analyzer.trackedFiles(in: repo)
        let code = GitLinguistAnalyzer().stats(repo: repo, scope: scope, trackedFiles: trackedFiles)
        let contributorResult = analyzer.contributorStatsResult(for: repo)
        let stats = GitRepoInspectorBaseStats(
            code: code,
            contributors: contributorResult.rows,
            contributorsWarning: contributorResult.warning
        )

        if let key, contributorResult.isCacheable {
            cache.writeBase(stats, for: key)
        }
        logDuration("Git base stats loaded", repo: repo, startedAt: startedAt)
        return stats
    }

    func codeOwnershipStats(
        for repo: GitRepo,
        scope: GitStatsScope,
        codeFilePaths: [String]
    ) async -> GitRepoCodeOwnershipStats {
        let startedAt = Date()
        let key = cacheKey(for: repo, scope: scope)
        if let key, let cached = cache.readOwnership(for: key) {
            Log.git.info("Git ownership stats cache hit for \(repo.displayName, privacy: .public)")
            return cached
        }

        if key != nil {
            Log.git.info("Git ownership stats cache miss for \(repo.displayName, privacy: .public)")
        }

        let stats = await ownershipAnalyzer.stats(repo: repo, codeFiles: codeFilePaths, scope: scope)
        if let key {
            cache.writeOwnership(stats, for: key)
        }
        logDuration("Git ownership stats loaded", repo: repo, startedAt: startedAt)
        return stats
    }

    private func cacheKey(for repo: GitRepo, scope: GitStatsScope) -> GitRepoStatsCache.Key? {
        guard scope == .head,
              let headHash = headHash(for: repo),
              let historySignature = historySignature(for: repo) else {
            return nil
        }
        return cache.key(
            repoRoot: repo.rootPath,
            scope: scope,
            headHash: headHash,
            historySignature: historySignature,
            runtimeSignature: runtimeSignature
        )
    }

    private func headHash(for repo: GitRepo) -> String? {
        let result = runner.run(["-C", repo.rootPath, "rev-parse", "HEAD"], timeout: 10)
        guard result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private func historySignature(for repo: GitRepo) -> String? {
        let result = runner.run(["-C", repo.rootPath, "show-ref", "--head", "--dereference"], timeout: 10)
        guard result.succeeded else { return nil }
        let normalized = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
        return normalized.nilIfBlank.map(Self.sha256)
    }

    private func logDuration(_ message: String, repo: GitRepo, startedAt: Date) {
        let duration = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        Log.git.info("\(message, privacy: .public) for \(repo.displayName, privacy: .public) in \(duration, privacy: .public)s")
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
