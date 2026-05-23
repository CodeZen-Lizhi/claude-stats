import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git repository watcher")
struct GitRepositoryWatcherTests {
    @Test("Watcher paths include worktree, git dir, refs, packed refs, index and HEAD")
    func watchPathsCoverRepoState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("git-watcher-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent(".git")
        let refsDir = gitDir.appendingPathComponent("refs")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        try Data().write(to: gitDir.appendingPathComponent("HEAD"))
        try Data().write(to: gitDir.appendingPathComponent("index"))
        try Data().write(to: gitDir.appendingPathComponent("packed-refs"))
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = GitRepo(
            rootPath: root.path,
            gitDirPath: gitDir.path,
            commonDirPath: gitDir.path,
            isWorktree: false,
            currentBranch: "main"
        )
        let paths = Set(GitRepositoryWatcher.watchPaths(for: repo))

        #expect(paths.contains(root.standardizedFileURL.path))
        #expect(paths.contains(gitDir.standardizedFileURL.path))
        #expect(paths.contains(refsDir.standardizedFileURL.path))
        #expect(paths.contains(gitDir.appendingPathComponent("HEAD").standardizedFileURL.path))
        #expect(paths.contains(gitDir.appendingPathComponent("index").standardizedFileURL.path))
        #expect(paths.contains(gitDir.appendingPathComponent("packed-refs").standardizedFileURL.path))
    }

    @Test("Watcher filters git internals without dropping real repo changes")
    func watcherFiltersEventPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("git-watcher-filter-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs/heads"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = GitRepo(
            rootPath: root.path,
            gitDirPath: gitDir.path,
            commonDirPath: gitDir.path,
            isWorktree: false,
            currentBranch: "main"
        )

        #expect(GitRepositoryWatcher.shouldRefresh(eventPath: root.appendingPathComponent("Sources/App.swift").path, repo: repo))
        #expect(GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("index").path, repo: repo))
        #expect(GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("HEAD").path, repo: repo))
        #expect(GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("refs/heads/main").path, repo: repo))
        #expect(GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("packed-refs").path, repo: repo))

        #expect(!GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("index.lock").path, repo: repo))
        #expect(!GitRepositoryWatcher.shouldRefresh(eventPath: gitDir.appendingPathComponent("objects/ab/cdef").path, repo: repo))
        #expect(!GitRepositoryWatcher.shouldRefresh(eventPath: root.appendingPathComponent(".build/debug/App.o").path, repo: repo))
        #expect(GitRepositoryWatcher.shouldRefresh(eventPaths: [
            gitDir.appendingPathComponent("objects/ab/cdef").path,
            root.appendingPathComponent("Sources/App.swift").path,
        ], repo: repo))
    }
}
