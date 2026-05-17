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
    private(set) var isStatsLoading = false
    private(set) var commitDetail: CommitDetail?
    private(set) var fileDiff: FileDiff?
    private(set) var repoStats: GitRepoInspectorStats?
    private(set) var currentRepoID: String?
    private(set) var loadedLimit = 0

    var statsScope: GitStatsScope = .head {
        didSet {
            guard oldValue != statsScope else { return }
            invalidateStatsRequest()
            repoStats = nil
        }
    }
    var selectedHash: String?
    var diffPath: String?
    var limit = 200

    private let isPreview: Bool
    @ObservationIgnored private var graphRequestID: UInt64 = 0
    @ObservationIgnored private var detailRequestID: UInt64 = 0
    @ObservationIgnored private var diffRequestID: UInt64 = 0
    @ObservationIgnored private var statsRequestID: UInt64 = 0

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
        repoStats = .preview
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

    var statsLoadID: String {
        "\(currentRepoID ?? "")|\(statsScope.rawValue)"
    }

    func loadGraph(repo: GitRepo) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview { return }
        if graph != nil, loadedLimit == limit { return }

        graphRequestID &+= 1
        let requestID = graphRequestID
        isGraphLoading = true
        defer { finishGraphRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedLimit = limit
        let loadedGraph = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().graph(for: repo, limit: requestedLimit)
        }.value

        guard graphRequestID == requestID,
              currentRepoID == requestedRepoID,
              limit == requestedLimit else { return }
        graph = loadedGraph
        layout = loadedGraph.map { GraphLayout.build($0.commits) }
        loadedLimit = requestedLimit
        reconcileSelection()
    }

    func loadDetail(repo: GitRepo) async {
        guard let hash = selectedHash else {
            invalidateDetailRequest()
            commitDetail = nil
            return
        }
        if isPreview { return }

        detailRequestID &+= 1
        let requestID = detailRequestID
        isDetailLoading = true
        defer { finishDetailRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedHash = hash
        let detail = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().commitDetail(for: requestedHash, in: repo)
        }.value

        guard detailRequestID == requestID,
              currentRepoID == requestedRepoID,
              selectedHash == requestedHash else { return }
        commitDetail = detail
    }

    func loadDiff(repo: GitRepo) async {
        guard let hash = selectedHash, let path = diffPath else {
            invalidateDiffRequest()
            fileDiff = nil
            return
        }
        if isPreview {
            #if DEBUG
            fileDiff = .preview(path: path)
            #endif
            return
        }

        diffRequestID &+= 1
        let requestID = diffRequestID
        isDiffLoading = true
        defer { finishDiffRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedHash = hash
        let requestedPath = path
        let diff = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().fileDiff(for: requestedHash, path: requestedPath, in: repo)
        }.value

        guard diffRequestID == requestID,
              currentRepoID == requestedRepoID,
              selectedHash == requestedHash,
              diffPath == requestedPath else { return }
        fileDiff = diff
    }

    func loadRepoStats(repo: GitRepo) async {
        if currentRepoID != repo.id {
            reset(for: repo)
        }
        if isPreview || repoStats != nil { return }

        statsRequestID &+= 1
        let requestID = statsRequestID
        isStatsLoading = true
        defer { finishStatsRequest(requestID) }

        let requestedRepoID = repo.id
        let requestedScope = statsScope
        let stats = await Task.detached(priority: .userInitiated) {
            GitAnalyzer().repoInspectorStats(for: repo, scope: requestedScope)
        }.value

        guard statsRequestID == requestID,
              currentRepoID == requestedRepoID,
              statsScope == requestedScope else { return }
        repoStats = stats
    }

    func selectCommit(_ hash: String) {
        guard selectedHash != hash else { return }
        invalidateDetailRequest()
        invalidateDiffRequest()
        selectedHash = hash
        commitDetail = nil
        diffPath = nil
        fileDiff = nil
    }

    func selectWorkingTree() {
        invalidateDetailRequest()
        invalidateDiffRequest()
        selectedHash = nil
        commitDetail = nil
        diffPath = nil
        fileDiff = nil
    }

    func openDiff(path: String) {
        guard diffPath != path else { return }
        invalidateDiffRequest()
        diffPath = path
        fileDiff = nil
    }

    func closeDiff() {
        invalidateDiffRequest()
        diffPath = nil
        fileDiff = nil
    }

    func loadMore() {
        limit += 200
    }

    private func reset(for repo: GitRepo) {
        invalidateGraphRequest()
        invalidateDetailRequest()
        invalidateDiffRequest()
        invalidateStatsRequest()
        currentRepoID = repo.id
        graph = nil
        layout = nil
        commitDetail = nil
        fileDiff = nil
        repoStats = nil
        selectedHash = nil
        diffPath = nil
        loadedLimit = 0
        limit = 200
        statsScope = .head
    }

    private func reconcileSelection() {
        guard let commits = graph?.commits, !commits.isEmpty else {
            invalidateDetailRequest()
            invalidateDiffRequest()
            selectedHash = nil
            commitDetail = nil
            diffPath = nil
            fileDiff = nil
            return
        }
        if let selectedHash, commits.contains(where: { $0.hash == selectedHash }) {
            return
        }
        invalidateDetailRequest()
        invalidateDiffRequest()
        selectedHash = nil
        commitDetail = nil
        diffPath = nil
        fileDiff = nil
    }

    private func invalidateGraphRequest() {
        graphRequestID &+= 1
        isGraphLoading = false
    }

    private func invalidateDetailRequest() {
        detailRequestID &+= 1
        isDetailLoading = false
    }

    private func invalidateDiffRequest() {
        diffRequestID &+= 1
        isDiffLoading = false
    }

    private func invalidateStatsRequest() {
        statsRequestID &+= 1
        isStatsLoading = false
    }

    private func finishGraphRequest(_ requestID: UInt64) {
        if graphRequestID == requestID {
            isGraphLoading = false
        }
    }

    private func finishDetailRequest(_ requestID: UInt64) {
        if detailRequestID == requestID {
            isDetailLoading = false
        }
    }

    private func finishDiffRequest(_ requestID: UInt64) {
        if diffRequestID == requestID {
            isDiffLoading = false
        }
    }

    private func finishStatsRequest(_ requestID: UInt64) {
        if statsRequestID == requestID {
            isStatsLoading = false
        }
    }
}

#if DEBUG
private extension GitRepoInspectorStats {
    static let preview = GitRepoInspectorStats(
        code: GitRepoCodeStats(
            engine: .linguist,
            scope: .head,
            warning: nil,
            totalFiles: 24,
            analyzedFiles: 19,
            skippedFiles: 5,
            totalBytes: 552_480,
            totalLines: 18_712,
            sourceLines: 15_920,
            codeFilePaths: [
                "ClaudeStats/App/ClaudeStatsApp.swift",
                "ClaudeStats/Services/GitAnalyzer.swift",
                "ClaudeStats/Views/Git/MainWindow/GitRepoWorkspaceView.swift",
                "project.yml",
                "scripts/run-debug.sh",
            ],
            languageRows: [
                .init(language: "Swift", fileCount: 14, sizeBytes: 489_600, byteShare: 0.886, totalLines: 17_313, sourceLines: 14_880),
                .init(language: "YAML", fileCount: 2, sizeBytes: 24_480, byteShare: 0.044, totalLines: 372, sourceLines: 320),
                .init(language: "Shell", fileCount: 2, sizeBytes: 17_880, byteShare: 0.032, totalLines: 360, sourceLines: 300),
                .init(language: "JSON", fileCount: 1, sizeBytes: 11_920, byteShare: 0.022, totalLines: 281, sourceLines: 260),
                .init(language: "Markdown", fileCount: 1, sizeBytes: 8_600, byteShare: 0.016, totalLines: 236, sourceLines: 160),
            ]
        ),
        codeContributors: [
            GitCodeContributionStat(name: "1pitaph", email: "xzltxy@163.com", lineCount: 15_840, share: 15_840.0 / 18_712.0),
            GitCodeContributionStat(name: "Codex", email: "codex@example.com", lineCount: 2_104, share: 2_104.0 / 18_712.0),
            GitCodeContributionStat(name: "Ada", email: "ada@example.com", lineCount: 768, share: 768.0 / 18_712.0),
        ],
        contributors: [
            GitContributorStat(name: "1pitaph", email: "xzltxy@163.com", commitCount: 46, share: 46.0 / 56.0),
            GitContributorStat(name: "Codex", email: "codex@example.com", commitCount: 7, share: 7.0 / 56.0),
            GitContributorStat(name: "Ada", email: "ada@example.com", commitCount: 3, share: 3.0 / 56.0),
        ]
    )
}
#endif
