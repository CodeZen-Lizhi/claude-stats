import Foundation

actor GitQueryCache {
    static let shared = GitQueryCache()

    private let ttl: TimeInterval
    private var graphPages: [String: CacheEntry<GitGraphPage>] = [:]
    private var commitDetails: [String: CacheEntry<CommitDetail>] = [:]
    private var fileDiffs: [String: CacheEntry<FileDiff>] = [:]
    private var fileChanges: [String: CacheEntry<[CommitFileChange]>] = [:]
    private var minimaps: [String: CacheEntry<GitGraphMinimapData>] = [:]

    private var graphPageTasks: [String: Task<GitGraphPage?, Never>] = [:]
    private var commitDetailTasks: [String: Task<CommitDetail?, Never>] = [:]
    private var fileDiffTasks: [String: Task<FileDiff?, Never>] = [:]
    private var fileChangeTasks: [String: Task<[CommitFileChange], Never>] = [:]
    private var minimapTasks: [String: Task<GitGraphMinimapData?, Never>] = [:]

    init(ttl: TimeInterval = 8) {
        self.ttl = ttl
    }

    func graphPage(key: String, load: @escaping @Sendable () -> GitGraphPage?) async -> GitGraphPage? {
        if let cached = fresh(graphPages[key]) { return cached }
        if let task = graphPageTasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        graphPageTasks[key] = task
        let value = await task.value
        graphPageTasks[key] = nil
        if let value { graphPages[key] = CacheEntry(value: value) }
        return value
    }

    func commitDetail(key: String, load: @escaping @Sendable () -> CommitDetail?) async -> CommitDetail? {
        if let cached = fresh(commitDetails[key]) { return cached }
        if let task = commitDetailTasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        commitDetailTasks[key] = task
        let value = await task.value
        commitDetailTasks[key] = nil
        if let value { commitDetails[key] = CacheEntry(value: value) }
        return value
    }

    func fileDiff(key: String, load: @escaping @Sendable () -> FileDiff?) async -> FileDiff? {
        if let cached = fresh(fileDiffs[key]) { return cached }
        if let task = fileDiffTasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        fileDiffTasks[key] = task
        let value = await task.value
        fileDiffTasks[key] = nil
        if let value { fileDiffs[key] = CacheEntry(value: value) }
        return value
    }

    func fileChanges(key: String, load: @escaping @Sendable () -> [CommitFileChange]) async -> [CommitFileChange] {
        if let cached = fresh(fileChanges[key]) { return cached }
        if let task = fileChangeTasks[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        fileChangeTasks[key] = task
        let value = await task.value
        fileChangeTasks[key] = nil
        fileChanges[key] = CacheEntry(value: value)
        return value
    }

    func minimap(key: String, load: @escaping @Sendable () -> GitGraphMinimapData?) async -> GitGraphMinimapData? {
        if let cached = fresh(minimaps[key]) { return cached }
        if let task = minimapTasks[key] { return await task.value }
        let task = Task.detached(priority: .utility) { load() }
        minimapTasks[key] = task
        let value = await task.value
        minimapTasks[key] = nil
        if let value { minimaps[key] = CacheEntry(value: value) }
        return value
    }

    func invalidate(repo: GitRepo) {
        let prefixes = [repo.cacheKey, repo.worktreeKey, repo.rootPath]
        graphPages = graphPages.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        commitDetails = commitDetails.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        fileDiffs = fileDiffs.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        fileChanges = fileChanges.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        minimaps = minimaps.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        graphPageTasks.values.forEach { $0.cancel() }
        commitDetailTasks.values.forEach { $0.cancel() }
        fileDiffTasks.values.forEach { $0.cancel() }
        fileChangeTasks.values.forEach { $0.cancel() }
        minimapTasks.values.forEach { $0.cancel() }
        graphPageTasks.removeAll()
        commitDetailTasks.removeAll()
        fileDiffTasks.removeAll()
        fileChangeTasks.removeAll()
        minimapTasks.removeAll()
    }

    private func fresh<Value: Sendable>(_ entry: CacheEntry<Value>?) -> Value? {
        guard let entry, Date().timeIntervalSince(entry.createdAt) <= ttl else { return nil }
        return entry.value
    }
}

private struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let createdAt = Date()
}
