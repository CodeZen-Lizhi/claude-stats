import Foundation
import Observation
import RockxyBackendEmbed

@MainActor
protocol NetworkHelperManaging: AnyObject {
    func refreshPassiveStatus() -> RockxyHelperSnapshot
    func refreshStatus() async -> RockxyHelperSnapshot
    func install() async throws -> RockxyHelperSnapshot
    func update() async throws -> RockxyHelperSnapshot
    func retryConnection() async -> RockxyHelperSnapshot
    func reinstall() async throws -> RockxyHelperSnapshot
    func openSystemSettingsLoginItems()
}

extension RockxyHelperController: NetworkHelperManaging {}

@MainActor
@Observable
final class NetworkDebuggerStore: @unchecked Sendable {
    var selectedSection: NetworkSection = .traffic
    var captureStatus: NetworkCaptureStatus = .stopped
    var systemProxyStatus: NetworkSystemProxyStatus = .idle
    var helperState: NetworkHelperState = .empty
    var certificateState: NetworkCertificateState = .empty
    var flows: [NetworkFlow] = []
    var selectedFlowID: UUID?
    var searchText = ""
    var selectedRequestTab: NetworkInspectorTab = .header
    var selectedResponseTab: NetworkInspectorTab = .body
    var selectedProtocol: NetworkFlowProtocol?
    var isSystemProxyWorking = false
    var isHelperWorking = false
    var isCertificateWorking = false

    private let proxyBackend: any NetworkProxyBackend
    private let systemProxyService: any NetworkSystemProxyManaging
    private let helperController: any NetworkHelperManaging
    private let certificateService = NetworkCertificateService()
    private weak var preferences: Preferences?
    private var autoEnabledSystemProxyForCurrentCapture = false

    init(
        preferences: Preferences? = nil,
        proxyBackend: any NetworkProxyBackend = RockxyNetworkProxyBackend(),
        systemProxyService: any NetworkSystemProxyManaging = NetworkSystemProxyService(),
        helperController: any NetworkHelperManaging = RockxyHelperController.shared
    ) {
        self.preferences = preferences
        self.proxyBackend = proxyBackend
        self.systemProxyService = systemProxyService
        self.helperController = helperController
    }

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

    var autoEnableSystemProxyOnStart: Bool {
        get { preferences?.networkAutoEnableSystemProxyOnStart ?? false }
        set { preferences?.networkAutoEnableSystemProxyOnStart = newValue }
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
        guard !captureStatus.isListening, captureStatus != .starting else { return }
        captureStatus = .starting
        autoEnabledSystemProxyForCurrentCapture = false
        Task { @MainActor in
            do {
                let endpoint = try await proxyBackend.start(preferredPorts: 9090...9099) { [weak self] event in
                    Task { @MainActor in
                        self?.apply(event)
                    }
                }
                captureStatus = .listening(endpoint)
                if preferences?.networkAutoEnableSystemProxyOnStart == true {
                    enableSystemProxy(autoTriggered: true)
                }
            } catch {
                captureStatus = .failed(error.localizedDescription)
            }
        }
    }

    func stopCapture() {
        let shouldRestoreAutoProxy = autoEnabledSystemProxyForCurrentCapture
        autoEnabledSystemProxyForCurrentCapture = false
        Task { @concurrent in
            await proxyBackend.stop()
        }
        captureStatus = .stopped
        if shouldRestoreAutoProxy {
            disableSystemProxy()
        }
    }

    func clearFlows() {
        flows.removeAll()
        selectedFlowID = nil
    }

    func refreshHelperStatus() {
        isHelperWorking = true
        Task { @MainActor in
            let snapshot = await helperController.refreshStatus()
            helperState = Self.helperState(from: snapshot)
            isHelperWorking = false
        }
    }

    func refreshPassiveHelperStatus() {
        isHelperWorking = true
        let snapshot = helperController.refreshPassiveStatus()
        helperState = Self.helperState(from: snapshot)
        isHelperWorking = false
    }

    func performHelperAction() {
        guard let action = helperState.action else { return }
        isHelperWorking = true
        Task { @MainActor in
            do {
                let snapshot: RockxyHelperSnapshot
                switch action {
                case .install:
                    snapshot = try await helperController.install()
                case .check:
                    snapshot = await helperController.refreshStatus()
                case .update:
                    snapshot = try await helperController.update()
                case .retry:
                    snapshot = await helperController.retryConnection()
                case .reinstall:
                    snapshot = try await helperController.reinstall()
                case .openSettings:
                    helperController.openSystemSettingsLoginItems()
                    snapshot = helperController.refreshPassiveStatus()
                }
                helperState = Self.helperState(from: snapshot)
            } catch {
                helperState.detailMessage = error.localizedDescription
            }
            isHelperWorking = false
        }
    }

    func enableSystemProxy() {
        enableSystemProxy(autoTriggered: false)
    }

    private func enableSystemProxy(autoTriggered: Bool) {
        guard let endpoint = listeningEndpoint else {
            captureStatus = .failed("Start the local proxy before enabling system proxy.")
            return
        }
        guard !systemProxyStatus.isEnabled else { return }
        isSystemProxyWorking = true
        Task { @concurrent in
            do {
                let status = try await systemProxyService.enable(endpoint: endpoint)
                await MainActor.run {
                    systemProxyStatus = status
                    if autoTriggered, status.isEnabled {
                        autoEnabledSystemProxyForCurrentCapture = true
                    }
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
        let currentState = certificateState
        Task { @concurrent in
            do {
                let state = try await certificateService.generateRootCA(preserving: currentState)
                await MainActor.run {
                    certificateState = state
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
        guard certificateState.rootCAPath != nil else {
            certificateState.statusMessage = "Generate a Root CA first."
            return
        }
        isCertificateWorking = true
        let currentState = certificateState
        Task { @concurrent in
            do {
                let state = try await certificateService.trustRootCA(preserving: currentState)
                await MainActor.run {
                    certificateState = state
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

    static func helperState(from snapshot: RockxyHelperSnapshot) -> NetworkHelperState {
        NetworkHelperState(
            statusMessage: snapshot.statusMessage,
            detailMessage: snapshot.lastErrorMessage,
            action: snapshot.action.map(NetworkHelperAction.init),
            isReachable: snapshot.isReachable,
            canUsePrivilegedHelper: snapshot.canUsePrivilegedHelper
        )
    }
}

private extension NetworkHelperAction {
    init(_ action: RockxyHelperAction) {
        switch action {
        case .install:
            self = .install
        case .check:
            self = .check
        case .update:
            self = .update
        case .retry:
            self = .retry
        case .reinstall:
            self = .reinstall
        case .openSettings:
            self = .openSettings
        }
    }
}
