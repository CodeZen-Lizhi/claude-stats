import Foundation

actor GitQueryCache {
    static let shared = GitQueryCache()

    private let ttl: TimeInterval
    private var graphPages: [String: CacheEntry<GitGraphPage>] = [:]
    private var commitDetails: [String: CacheEntry<CommitDetail>] = [:]
    private var fileDiffs: [String: CacheEntry<FileDiff>] = [:]
    private var fileChanges: [String: CacheEntry<[CommitFileChange]>] = [:]
    private var minimaps: [String: CacheEntry<GitGraphMinimapData>] = [:]

    private var graphPageTasks: [String: InflightTask<GitGraphPage?>] = [:]
    private var commitDetailTasks: [String: InflightTask<CommitDetail?>] = [:]
    private var fileDiffTasks: [String: InflightTask<FileDiff?>] = [:]
    private var fileChangeTasks: [String: InflightTask<[CommitFileChange]>] = [:]
    private var minimapTasks: [String: InflightTask<GitGraphMinimapData?>] = [:]

    init(ttl: TimeInterval = 8) {
        self.ttl = ttl
    }

    func graphPage(key: String, load: @escaping @Sendable () -> GitGraphPage?) async -> GitGraphPage? {
        if let cached = fresh(graphPages[key]) { return cached }
        if let inflight = graphPageTasks[key] { return await inflight.task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        let inflight = InflightTask(task: task)
        graphPageTasks[key] = inflight
        let value = await task.value
        guard graphPageTasks[key]?.token == inflight.token else { return nil }
        graphPageTasks[key] = nil
        if let value { graphPages[key] = CacheEntry(value: value) }
        return value
    }

    func commitDetail(key: String, load: @escaping @Sendable () -> CommitDetail?) async -> CommitDetail? {
        if let cached = fresh(commitDetails[key]) { return cached }
        if let inflight = commitDetailTasks[key] { return await inflight.task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        let inflight = InflightTask(task: task)
        commitDetailTasks[key] = inflight
        let value = await task.value
        guard commitDetailTasks[key]?.token == inflight.token else { return nil }
        commitDetailTasks[key] = nil
        if let value { commitDetails[key] = CacheEntry(value: value) }
        return value
    }

    func fileDiff(key: String, load: @escaping @Sendable () -> FileDiff?) async -> FileDiff? {
        if let cached = fresh(fileDiffs[key]) { return cached }
        if let inflight = fileDiffTasks[key] { return await inflight.task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        let inflight = InflightTask(task: task)
        fileDiffTasks[key] = inflight
        let value = await task.value
        guard fileDiffTasks[key]?.token == inflight.token else { return nil }
        fileDiffTasks[key] = nil
        if let value { fileDiffs[key] = CacheEntry(value: value) }
        return value
    }

    func fileChanges(key: String, load: @escaping @Sendable () -> [CommitFileChange]) async -> [CommitFileChange] {
        if let cached = fresh(fileChanges[key]) { return cached }
        if let inflight = fileChangeTasks[key] { return await inflight.task.value }
        let task = Task.detached(priority: .userInitiated) { load() }
        let inflight = InflightTask(task: task)
        fileChangeTasks[key] = inflight
        let value = await task.value
        guard fileChangeTasks[key]?.token == inflight.token else { return [] }
        fileChangeTasks[key] = nil
        fileChanges[key] = CacheEntry(value: value)
        return value
    }

    func minimap(key: String, load: @escaping @Sendable () -> GitGraphMinimapData?) async -> GitGraphMinimapData? {
        if let cached = fresh(minimaps[key]) { return cached }
        if let inflight = minimapTasks[key] { return await inflight.task.value }
        let task = Task.detached(priority: .utility) { load() }
        let inflight = InflightTask(task: task)
        minimapTasks[key] = inflight
        let value = await task.value
        guard minimapTasks[key]?.token == inflight.token else { return nil }
        minimapTasks[key] = nil
        if let value { minimaps[key] = CacheEntry(value: value) }
        return value
    }

    func invalidate(repo: GitRepo) {
        let prefixes = [repo.cacheKey, repo.worktreeKey, repo.rootPath]
        graphPages = graphPages.filter { key, _ in !matches(key, prefixes: prefixes) }
        commitDetails = commitDetails.filter { key, _ in !matches(key, prefixes: prefixes) }
        fileDiffs = fileDiffs.filter { key, _ in !matches(key, prefixes: prefixes) }
        fileChanges = fileChanges.filter { key, _ in !matches(key, prefixes: prefixes) }
        minimaps = minimaps.filter { key, _ in !matches(key, prefixes: prefixes) }
        cancelMatching(&graphPageTasks, prefixes: prefixes)
        cancelMatching(&commitDetailTasks, prefixes: prefixes)
        cancelMatching(&fileDiffTasks, prefixes: prefixes)
        cancelMatching(&fileChangeTasks, prefixes: prefixes)
        cancelMatching(&minimapTasks, prefixes: prefixes)
    }

    private func fresh<Value: Sendable>(_ entry: CacheEntry<Value>?) -> Value? {
        guard let entry, Date().timeIntervalSince(entry.createdAt) <= ttl else { return nil }
        return entry.value
    }

    private func matches(_ key: String, prefixes: [String]) -> Bool {
        prefixes.contains { prefix in
            key == prefix || key.hasPrefix("\(prefix)|")
        }
    }

    private func cancelMatching<Value: Sendable>(
        _ tasks: inout [String: InflightTask<Value>],
        prefixes: [String]
    ) {
        let keys = tasks.keys.filter { matches($0, prefixes: prefixes) }
        for key in keys {
            tasks[key]?.task.cancel()
            tasks[key] = nil
        }
    }
}

private struct InflightTask<Value: Sendable>: Sendable {
    let token = UUID()
    let task: Task<Value, Never>
}

private struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let createdAt = Date()
}
