import Foundation
@preconcurrency import CoreServices

final class GitRepositoryWatcher: @unchecked Sendable {
    private let repo: GitRepo
    private let paths: [String]
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.claudestats.git.repository-watcher", qos: .utility)

    private var stream: FSEventStreamRef?
    private var pendingChange: DispatchWorkItem?

    init(repo: GitRepo, debounceInterval: TimeInterval = 0.75, onChange: @escaping @Sendable () -> Void) {
        self.repo = repo
        self.paths = Self.watchPaths(for: repo)
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let created = FSEventStreamCreate(
            nil,
            gitRepositoryWatcherCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pendingChange = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    fileprivate func handleEvent(rawPaths: UnsafeMutableRawPointer, count: Int) {
        let paths = Self.eventPaths(from: rawPaths, count: count)
        guard Self.shouldRefresh(eventPaths: paths, repo: repo) else { return }
        scheduleChange()
    }

    static func watchPaths(for repo: GitRepo) -> [String] {
        let fileManager = FileManager.default
        let candidates = [
            repo.rootPath,
            repo.gitDirPath,
            repo.commonDirPath,
            repo.commonDirPath.map { ($0 as NSString).appendingPathComponent("refs") },
            repo.commonDirPath.map { ($0 as NSString).appendingPathComponent("packed-refs") },
            repo.gitDirPath.map { ($0 as NSString).appendingPathComponent("index") },
            repo.gitDirPath.map { ($0 as NSString).appendingPathComponent("HEAD") },
        ].compactMap { $0 }

        var seen = Set<String>()
        return candidates.compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard fileManager.fileExists(atPath: standardized), seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }

    static func shouldRefresh(eventPath path: String, repo: GitRepo) -> Bool {
        let eventPath = standardized(path)
        let rootPath = standardized(repo.rootPath)
        let gitDirPath = repo.gitDirPath.map(standardized)
        let commonDirPath = repo.commonDirPath.map(standardized)

        if let gitDirPath, contains(path: eventPath, in: gitDirPath) {
            return isRefreshRelevantGitPath(eventPath, gitDirPath: gitDirPath, commonDirPath: commonDirPath)
        }
        if let commonDirPath, contains(path: eventPath, in: commonDirPath) {
            return isRefreshRelevantGitPath(eventPath, gitDirPath: gitDirPath, commonDirPath: commonDirPath)
        }
        if contains(path: eventPath, in: rootPath) {
            return isRefreshRelevantWorktreePath(eventPath, rootPath: rootPath)
        }
        return false
    }

    static func shouldRefresh(eventPaths paths: [String], repo: GitRepo) -> Bool {
        paths.isEmpty || paths.contains { shouldRefresh(eventPath: $0, repo: repo) }
    }

    private static func isRefreshRelevantGitPath(_ path: String, gitDirPath: String?, commonDirPath: String?) -> Bool {
        if path.hasSuffix(".lock") { return false }
        if let gitDirPath {
            if path == gitDirPath { return true }
            if path == gitDirPath.appendingPathComponent("HEAD") { return true }
            if path == gitDirPath.appendingPathComponent("index") { return true }
            if path == gitDirPath.appendingPathComponent("MERGE_HEAD") { return true }
            if path == gitDirPath.appendingPathComponent("rebase-merge") { return true }
            if path == gitDirPath.appendingPathComponent("rebase-apply") { return true }
            if contains(path: path, in: gitDirPath.appendingPathComponent("refs")) { return true }
        }
        if let commonDirPath {
            if path == commonDirPath { return true }
            if path == commonDirPath.appendingPathComponent("packed-refs") { return true }
            if contains(path: path, in: commonDirPath.appendingPathComponent("refs")) { return true }
        }
        return false
    }

    private static func isRefreshRelevantWorktreePath(_ path: String, rootPath: String) -> Bool {
        let ignoredDirectories = [".git", ".build", "DerivedData", "node_modules"]
        for directory in ignoredDirectories {
            if contains(path: path, in: rootPath.appendingPathComponent(directory)) {
                return false
            }
        }
        return true
    }

    private static func contains(path: String, in parent: String) -> Bool {
        path == parent || path.hasPrefix(parent.appendingPathComponent(""))
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    fileprivate static func eventPaths(from rawPaths: UnsafeMutableRawPointer, count: Int) -> [String] {
        guard count > 0 else { return [] }
        let paths = rawPaths.bindMemory(to: UnsafePointer<CChar>.self, capacity: count)
        return (0..<count).compactMap { String(validatingUTF8: paths[$0]) }
    }
}

private func gitRepositoryWatcherCallback(
    _: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    count: Int,
    eventPaths: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<GitRepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
    watcher.handleEvent(rawPaths: eventPaths, count: count)
}

private extension String {
    func appendingPathComponent(_ component: String) -> String {
        (self as NSString).appendingPathComponent(component)
    }
}
