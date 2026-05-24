import Foundation
import Observation

struct TranscriptAnalysisProviderState: Equatable, Sendable {
    var snapshot: TranscriptAnalysisSnapshot?
    var progress = TranscriptAnalysisProgress.idle
    var isLoading = false
    var errorMessage: String?
    var loadedSignature: String?
    var loadingSignature: String?
}

@MainActor
@Observable
final class TranscriptAnalysisStore {
    private(set) var statesByProvider: [ProviderKind: TranscriptAnalysisProviderState] = [:]

    @ObservationIgnored private let service: TranscriptAnalysisService
    @ObservationIgnored private var loadTasks: [ProviderKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var runIDs: [ProviderKind: UUID] = [:]

    init(service: TranscriptAnalysisService = TranscriptAnalysisService()) {
        self.service = service
    }

    func loadIfNeeded(
        provider: ProviderKind,
        sessions: [Session],
        messageLoader: TranscriptMessageLoader?
    ) {
        let signature = TranscriptAnalysisService.corpusSignature(for: sessions)
        let state = state(for: provider)
        if state.loadedSignature == signature, state.snapshot != nil {
            return
        }
        if state.isLoading, state.loadingSignature == signature {
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
        load(
            provider: provider,
            sessions: sessions,
            signature: TranscriptAnalysisService.corpusSignature(for: sessions),
            messageLoader: messageLoader,
            forceRefresh: true
        )
    }

    func snapshot(for provider: ProviderKind) -> TranscriptAnalysisSnapshot? {
        statesByProvider[provider]?.snapshot
    }

    func progress(for provider: ProviderKind) -> TranscriptAnalysisProgress {
        statesByProvider[provider]?.progress ?? .idle
    }

    func isLoading(for provider: ProviderKind) -> Bool {
        statesByProvider[provider]?.isLoading ?? false
    }

    func errorMessage(for provider: ProviderKind) -> String? {
        statesByProvider[provider]?.errorMessage
    }

    func sessionAnalysis(for sessionID: String, provider: ProviderKind? = nil) -> TranscriptSessionAnalysis? {
        if let provider {
            return snapshot(for: provider)?.sessionAnalysis(for: sessionID)
        }
        return statesByProvider.values
            .compactMap(\.snapshot)
            .first { $0.sessionAnalysis(for: sessionID) != nil }?
            .sessionAnalysis(for: sessionID)
    }

    private func load(
        provider: ProviderKind,
        sessions: [Session],
        signature: String,
        messageLoader: TranscriptMessageLoader?,
        forceRefresh: Bool
    ) {
        guard let messageLoader else {
            updateState(for: provider) { state in
                state.errorMessage = "No transcript loader is available for \(provider.shortName)."
                state.isLoading = false
                state.loadingSignature = nil
                state.progress = .idle
            }
            return
        }

        let runID = UUID()
        runIDs[provider] = runID
        loadTasks[provider]?.cancel()

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
        updateState(for: provider) { state in
            state.isLoading = true
            state.loadingSignature = signature
            state.progress = initialProgress
            state.errorMessage = nil
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
                            self.updateState(for: provider) { state in
                                state.progress = progress
                            }
                        }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.runIDs[provider] == runID else { return }
                    self.finishLoading(provider: provider, runID: runID) { state in
                        state.snapshot = result
                        state.loadedSignature = signature
                        state.progress = .idle
                        state.errorMessage = nil
                    }
                    Log.analysis.info(
                        "Transcript analysis refreshed for \(provider.rawValue, privacy: .public): \(result.analyzedSessionCount, privacy: .public) analyzed sessions in \(Date().timeIntervalSince(started), privacy: .public)s"
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.finishLoading(provider: provider, runID: runID) { state in
                        state.progress = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.runIDs[provider] == runID else { return }
                    self.finishLoading(provider: provider, runID: runID) { state in
                        state.errorMessage = error.localizedDescription
                        state.progress = .idle
                    }
                    Log.analysis.error("Transcript analysis failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func finishLoading(
        provider: ProviderKind,
        runID: UUID,
        update: ((inout TranscriptAnalysisProviderState) -> Void)? = nil
    ) {
        guard runIDs[provider] == runID else { return }
        loadTasks[provider] = nil
        updateState(for: provider) { state in
            update?(&state)
            state.isLoading = false
            state.loadingSignature = nil
        }
    }

    private func state(for provider: ProviderKind) -> TranscriptAnalysisProviderState {
        statesByProvider[provider] ?? TranscriptAnalysisProviderState()
    }

    private func updateState(
        for provider: ProviderKind,
        _ update: (inout TranscriptAnalysisProviderState) -> Void
    ) {
        var state = state(for: provider)
        update(&state)
        statesByProvider[provider] = state
    }
}
