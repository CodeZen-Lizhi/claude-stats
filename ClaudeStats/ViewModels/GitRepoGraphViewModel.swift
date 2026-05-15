import Foundation
import Observation

@MainActor
@Observable
final class GitRepoGraphViewModel {
    private(set) var graph: GitGraph?
    private(set) var layout: GraphLayout?
    private(set) var isGraphLoading = false
    private(set) var isDetailLoading = false
    private(set) var isDiffLoading = false
    private(set) var commitDetail: CommitDetail?
    private(set) var fileDiff: FileDiff?
    private(set) var currentRepoID: String?
    private(set) var loadedLimit = 0

    var selectedHash: String?
    var diffPath: String?
    var limit = 200

    private let isPreview: Bool

    init() {
        isPreview = false
    }

    #if DEBUG
    init(previewGraph: GitGraph) {
        graph = previewGraph
        layout = GraphLayout.build(previewGraph.commits)
        currentRepoID = previewGraph.repo.id
        loadedLimit = previewGraph.commits.count
        selectedHash = previewGraph.commits.first?.hash
        if let commit = previewGraph.commits.first {
            commitDetail = .preview(
                from: commit,
                files: GitGraph.previewFileChanges()[commit.hash] ?? []
            )
        }
        isPreview = true
    }
    #endif

    var selectedCommit: GraphCommit? {
        guard let selectedHash else { return nil }
        return graph?.commits.first { $0.hash == selectedHash }
    }

    var graphLoadID: String {
        "\(currentRepoID ?? "")|\(limit)"
    }

    var detailLoadID: String {
        "\(currentRepoID ?? "")|\(selectedHash ?? "")"
    }

    var diffLoadID: String {
        "\(currentRepoID ?? "")|\(selectedHash ?? "")|\(diffPath ?? "")"
    }

    func loadGraph(repo: GitRepo) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview { return }
        if graph != nil, loadedLimit == limit { return }

        isGraphLoading = true
        let requestedRepoID = repo.id
        let requestedLimit = limit
        let loadedGraph = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().graph(for: repo, limit: requestedLimit)
        }.value

        guard currentRepoID == requestedRepoID, limit == requestedLimit else { return }
        graph = loadedGraph
        layout = loadedGraph.map { GraphLayout.build($0.commits) }
        loadedLimit = requestedLimit
        reconcileSelection()
        isGraphLoading = false
    }

    func loadDetail(repo: GitRepo) async {
        guard let hash = selectedHash else {
            commitDetail = nil
            return
        }
        if isPreview { return }

        isDetailLoading = true
        let requestedRepoID = repo.id
        let requestedHash = hash
        let detail = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().commitDetail(for: requestedHash, in: repo)
        }.value

        guard currentRepoID == requestedRepoID, selectedHash == requestedHash else { return }
        commitDetail = detail
        isDetailLoading = false
    }

    func loadDiff(repo: GitRepo) async {
        guard let hash = selectedHash, let path = diffPath else {
            fileDiff = nil
            return
        }
        if isPreview {
            #if DEBUG
            fileDiff = .preview(path: path)
            #endif
            return
        }

        isDiffLoading = true
        let requestedRepoID = repo.id
        let requestedHash = hash
        let requestedPath = path
        let diff = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().fileDiff(for: requestedHash, path: requestedPath, in: repo)
        }.value

        guard currentRepoID == requestedRepoID,
              selectedHash == requestedHash,
              diffPath == requestedPath else { return }
        fileDiff = diff
        isDiffLoading = false
    }

    func selectCommit(_ hash: String) {
        guard selectedHash != hash else { return }
        selectedHash = hash
        commitDetail = nil
        diffPath = nil
        fileDiff = nil
    }

    func openDiff(path: String) {
        guard diffPath != path else { return }
        diffPath = path
        fileDiff = nil
    }

    func closeDiff() {
        diffPath = nil
        fileDiff = nil
        isDiffLoading = false
    }

    func loadMore() {
        limit += 200
    }

    private func reset(for repo: GitRepo) {
        currentRepoID = repo.id
        graph = nil
        layout = nil
        commitDetail = nil
        fileDiff = nil
        selectedHash = nil
        diffPath = nil
        loadedLimit = 0
        limit = 200
        isGraphLoading = false
        isDetailLoading = false
        isDiffLoading = false
    }

    private func reconcileSelection() {
        guard let commits = graph?.commits, !commits.isEmpty else {
            selectedHash = nil
            commitDetail = nil
            diffPath = nil
            fileDiff = nil
            return
        }
        if let selectedHash, commits.contains(where: { $0.hash == selectedHash }) {
            return
        }
        selectedHash = commits.first?.hash
        commitDetail = nil
        diffPath = nil
        fileDiff = nil
    }
}
