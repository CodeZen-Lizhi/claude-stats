import Foundation
import Observation

@MainActor
@Observable
final class NetworkDebuggerStore: @unchecked Sendable {
    var selectedSection: NetworkSection = .traffic
    var captureStatus: NetworkCaptureStatus = .stopped
    var systemProxyStatus: NetworkSystemProxyStatus = .idle
    var certificateState: NetworkCertificateState = .empty
    var flows: [NetworkFlow] = []
    var selectedFlowID: UUID?
    var searchText = ""
    var selectedRequestTab: NetworkInspectorTab = .header
    var selectedResponseTab: NetworkInspectorTab = .body
    var selectedInspectorSide: NetworkInspectorSide = .request
    var selectedProtocol: NetworkFlowProtocol?
    var isSystemProxyWorking = false
    var isCertificateWorking = false

    private let proxyService = NetworkProxyService()
    private let systemProxyService = NetworkSystemProxyService()
    private let certificateService = NetworkCertificateService()

    var selectedFlow: NetworkFlow? {
        guard let selectedFlowID else { return flows.first }
        return flows.first { $0.id == selectedFlowID } ?? flows.first
    }

    var filteredFlows: [NetworkFlow] {
        flows.filter { flow in
            let matchesProtocol = selectedProtocol == nil || flow.flowProtocol == selectedProtocol
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesProtocol }
            return matchesProtocol && (
                flow.request.url.localizedCaseInsensitiveContains(query)
                || flow.request.method.localizedCaseInsensitiveContains(query)
                || flow.clientName.localizedCaseInsensitiveContains(query)
                || flow.statusDisplay.localizedCaseInsensitiveContains(query)
            )
        }
    }

    var listeningEndpoint: NetworkProxyEndpoint? {
        if case .listening(let endpoint) = captureStatus { return endpoint }
        return nil
    }

    var statusMessage: String {
        switch captureStatus {
        case .stopped: "Proxy stopped"
        case .starting: "Starting proxy..."
        case .listening(let endpoint): "Listening on \(endpoint.displayName)"
        case .failed(let message): message
        }
    }

    func startCapture() {
        guard !captureStatus.isListening else { return }
        captureStatus = .starting
        do {
            let endpoint = try proxyService.start(preferredPorts: 9090...9099) { [weak self] event in
                Task { @MainActor in
                    self?.apply(event)
                }
            }
            captureStatus = .listening(endpoint)
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    func stopCapture() {
        proxyService.stop()
        captureStatus = .stopped
    }

    func clearFlows() {
        flows.removeAll()
        selectedFlowID = nil
    }

    func enableSystemProxy() {
        guard let endpoint = listeningEndpoint else {
            captureStatus = .failed("Start the local proxy before enabling system proxy.")
            return
        }
        isSystemProxyWorking = true
        Task { @concurrent in
            do {
                let status = try await systemProxyService.enable(endpoint: endpoint)
                await MainActor.run {
                    systemProxyStatus = status
                    isSystemProxyWorking = false
                }
            } catch {
                await MainActor.run {
                    systemProxyStatus.lastError = error.localizedDescription
                    isSystemProxyWorking = false
                }
            }
        }
    }

    func disableSystemProxy() {
        let services = systemProxyStatus.managedServices
        isSystemProxyWorking = true
        Task { @concurrent in
            do {
                let status = try await systemProxyService.disable(services: services)
                await MainActor.run {
                    systemProxyStatus = status
                    isSystemProxyWorking = false
                }
            } catch {
                await MainActor.run {
                    systemProxyStatus.lastError = error.localizedDescription
                    isSystemProxyWorking = false
                }
            }
        }
    }

    func generateRootCA() {
        isCertificateWorking = true
        Task { @concurrent in
            do {
                let path = try await certificateService.generateRootCA()
                await MainActor.run {
                    certificateState.rootCAPath = path
                    certificateState.statusMessage = "Root CA generated."
                    isCertificateWorking = false
                }
            } catch {
                await MainActor.run {
                    certificateState.statusMessage = error.localizedDescription
                    isCertificateWorking = false
                }
            }
        }
    }

    func trustRootCA() {
        guard let path = certificateState.rootCAPath else {
            certificateState.statusMessage = "Generate a Root CA first."
            return
        }
        isCertificateWorking = true
        Task { @concurrent in
            do {
                try await certificateService.trustRootCA(path: path)
                await MainActor.run {
                    certificateState.isTrusted = true
                    certificateState.statusMessage = "Root CA trusted in login keychain."
                    isCertificateWorking = false
                }
            } catch {
                await MainActor.run {
                    certificateState.statusMessage = error.localizedDescription
                    isCertificateWorking = false
                }
            }
        }
    }

    func addSSLHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !certificateState.sslHostAllowlist.contains(trimmed) else { return }
        certificateState.sslHostAllowlist.append(trimmed)
    }

    func removeSSLHost(_ host: String) {
        certificateState.sslHostAllowlist.removeAll { $0 == host }
    }

    private func apply(_ event: NetworkProxyEvent) {
        switch event {
        case .started(let endpoint):
            captureStatus = .listening(endpoint)
            Log.network.info("Network proxy listening on \(endpoint.displayName, privacy: .public)")
        case .stopped:
            if captureStatus.isListening { captureStatus = .stopped }
        case .flowCreated(let flow):
            flows.insert(flow, at: 0)
            selectedFlowID = selectedFlowID ?? flow.id
        case .flowUpdated(let flow):
            if let index = flows.firstIndex(where: { $0.id == flow.id }) {
                flows[index] = flow
            } else {
                flows.insert(flow, at: 0)
            }
        case .failed(let message):
            captureStatus = .failed(message)
            Log.network.error("Network proxy failed: \(message, privacy: .public)")
        }
    }
}
