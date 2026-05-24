import Foundation
import Observation

@MainActor
@Observable
final class TranscriptAnalysisStore {
    private(set) var snapshot: TranscriptAnalysisSnapshot?
    private(set) var progress = TranscriptAnalysisProgress.idle
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: TranscriptAnalysisService
    @ObservationIgnored private var loadTasks: [ProviderKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var runIDs: [ProviderKind: UUID] = [:]
    @ObservationIgnored private var loadedSignatures: [ProviderKind: String] = [:]
    @ObservationIgnored private var snapshotsByProvider: [ProviderKind: TranscriptAnalysisSnapshot] = [:]
    @ObservationIgnored private var progressByProvider: [ProviderKind: TranscriptAnalysisProgress] = [:]
    @ObservationIgnored private var loadingProviders: Set<ProviderKind> = []
    @ObservationIgnored private var activeProvider: ProviderKind?

    init(service: TranscriptAnalysisService = TranscriptAnalysisService()) {
        self.service = service
    }

    func loadIfNeeded(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: TranscriptMessageLoader?
    ) {
        activeProvider = provider
        snapshot = snapshotsByProvider[provider]
        progress = progressByProvider[provider] ?? .idle

        let signature = TranscriptAnalysisService.corpusSignature(for: sessions)
        if loadedSignatures[provider] == signature,
           snapshotsByProvider[provider] != nil || loadingProviders.contains(provider) {
            updateLoadingState()
            return
        }
        load(
            provider: provider,
            sessions: sessions,
            signature: signature,
            messageLoader: messageLoader,
            forceRefresh: false
        )
    }

    func reload(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: TranscriptMessageLoader?
    ) {
        activeProvider = provider
        load(
            provider: provider,
            sessions: sessions,
            signature: TranscriptAnalysisService.corpusSignature(for: sessions),
            messageLoader: messageLoader,
            forceRefresh: true
        )
    }

    func snapshot(for provider: ProviderKind) -> TranscriptAnalysisSnapshot? {
        snapshot?.provider == provider ? snapshot : snapshotsByProvider[provider]
    }

    func progress(for provider: ProviderKind) -> TranscriptAnalysisProgress {
        progressByProvider[provider] ?? .idle
    }

    func isLoading(for provider: ProviderKind) -> Bool {
        loadingProviders.contains(provider)
    }

    func sessionAnalysis(for sessionID: String, provider: ProviderKind? = nil) -> TranscriptSessionAnalysis? {
        if let provider {
            return snapshot(for: provider)?.sessionAnalysis(for: sessionID)
        }
        return snapshot?.sessionAnalysis(for: sessionID)
    }

    private func load(
        provider: ProviderKind,
        sessions: [Session],
        signature: String,
        messageLoader: TranscriptMessageLoader?,
        forceRefresh: Bool
    ) {
        guard let messageLoader else {
            errorMessage = "No transcript loader is available for \(provider.shortName)."
            return
        }

        let runID = UUID()
        runIDs[provider] = runID
        loadTasks[provider]?.cancel()
        loadingProviders.insert(provider)
        isLoading = true
        errorMessage = nil

        let initialProgress = TranscriptAnalysisProgress(
            phase: .loadingIndex,
            total: sessions.count,
            completed: 0,
            reused: 0,
            newCount: 0,
            changed: 0,
            empty: 0,
            deleted: 0,
            currentSessionTitle: nil
        )
        progressByProvider[provider] = initialProgress
        if activeProvider == provider {
            progress = initialProgress
        }

        loadTasks[provider] = Task { [service, messageLoader] in
            do {
                let started = Date()
                let result = try await service.analyze(
                    provider: provider,
                    sessions: sessions,
                    messageLoader: messageLoader,
                    forceRefresh: forceRefresh,
                    onProgress: { progress in
                        await MainActor.run {
                            guard self.runIDs[provider] == runID else { return }
                            self.progressByProvider[provider] = progress
                            if self.activeProvider == provider {
                                self.progress = progress
                            }
                        }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.runIDs[provider] == runID else { return }
                    self.snapshotsByProvider[provider] = result
                    self.loadedSignatures[provider] = signature
                    self.progressByProvider[provider] = .idle
                    if self.activeProvider == provider {
                        self.snapshot = result
                        self.progress = .idle
                    }
                    self.finishLoading(provider: provider, runID: runID)
                    Log.analysis.info(
                        "Transcript analysis refreshed for \(provider.rawValue, privacy: .public): \(result.analyzedSessionCount, privacy: .public) analyzed sessions in \(Date().timeIntervalSince(started), privacy: .public)s"
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.finishLoading(provider: provider, runID: runID)
                }
            } catch {
                await MainActor.run {
                    guard self.runIDs[provider] == runID else { return }
                    self.errorMessage = error.localizedDescription
                    if self.activeProvider == provider {
                        self.progress = .idle
                    }
                    self.progressByProvider[provider] = .idle
                    self.finishLoading(provider: provider, runID: runID)
                    Log.analysis.error("Transcript analysis failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func finishLoading(provider: ProviderKind, runID: UUID) {
        guard runIDs[provider] == runID else { return }
        loadTasks[provider] = nil
        loadingProviders.remove(provider)
        updateLoadingState()
    }

    private func updateLoadingState() {
        isLoading = !loadingProviders.isEmpty
    }
}
