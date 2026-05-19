import AppKit
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
    var selectedRequestTab: NetworkInspectorTab = .header
    var selectedResponseTab: NetworkInspectorTab = .body
    var trafficSidebarLayer: NetworkTrafficSidebarLayer = .sections
    var trafficFilter = NetworkTrafficFilter()
    var isSystemProxyWorking = false
    var isHelperWorking = false
    var isUpstreamProxyWorking = false
    var isCertificateWorking = false
    var isRulesWorking = false
    var isPluginsWorking = false
    var isReplayWorking = false
    var upstreamProxyConfirmation: NetworkUpstreamProxyConfirmation?
    var upstreamProxyTestResult: NetworkUpstreamProxyTestResult?
    var upstreamProxyStatusMessage: String?
    var rules: [NetworkRuleDraft] = []
    var selectedRuleID: UUID?
    var ruleMatchResult: NetworkRuleMatchSnapshot?
    var ruleStatusMessage: String?
    var plugins: [NetworkPluginItem] = []
    var pluginStatusMessage: String?
    var breakpoints: [NetworkBreakpointItem] = []
    var selectedBreakpointID: UUID?
    var replayDraft: NetworkReplayDraft?
    var manualUpstreamProxyPassword = ""

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
            matchesTrafficFilter(flow)
        }
    }

    var selectedRule: NetworkRuleDraft? {
        guard let selectedRuleID else { return rules.first }
        return rules.first { $0.id == selectedRuleID } ?? rules.first
    }

    var trafficApps: [NetworkTrafficFilterGroup] {
        groupedFilters(
            flows.map { $0.clientName.isEmpty ? "Unknown" : $0.clientName },
            symbol: "app"
        )
    }

    var trafficDomains: [NetworkTrafficFilterGroup] {
        groupedFilters(flows.map(\.domainDisplay), symbol: "globe")
    }

    var trafficMethods: [NetworkTrafficFilterGroup] {
        groupedFilters(flows.map(\.methodDisplay), symbol: "arrow.right.circle")
    }

    var pinnedTrafficCount: Int {
        flows.filter(\.isPinned).count
    }

    var savedTrafficCount: Int {
        flows.filter(\.isSaved).count
    }

    func statusCount(for status: NetworkTrafficStatusFilter) -> Int {
        flows.filter(status.matches).count
    }

    func protocolCount(for proto: NetworkFlowProtocol) -> Int {
        flows.filter { $0.flowProtocol == proto }.count
    }

    var listeningEndpoint: NetworkProxyEndpoint? {
        if case .listening(let endpoint) = captureStatus { return endpoint }
        return nil
    }

    var autoEnableSystemProxyOnStart: Bool {
        get { preferences?.networkAutoEnableSystemProxyOnStart ?? false }
        set { preferences?.networkAutoEnableSystemProxyOnStart = newValue }
    }

    var searchText: String {
        get { trafficFilter.query }
        set { trafficFilter.query = newValue }
    }

    var selectedProtocol: NetworkFlowProtocol? {
        get { trafficFilter.protocols.count == 1 ? trafficFilter.protocols.first : nil }
        set {
            if let newValue {
                trafficFilter.protocols = [newValue]
            } else {
                trafficFilter.protocols = []
            }
        }
    }

    var upstreamProxyMode: NetworkUpstreamProxyMode {
        get { preferences?.networkUpstreamProxyMode ?? .automatic }
        set { preferences?.networkUpstreamProxyMode = newValue }
    }

    var askBeforeChainingExistingSystemProxy: Bool {
        get { preferences?.networkAskBeforeChainingExistingSystemProxy ?? false }
        set { preferences?.networkAskBeforeChainingExistingSystemProxy = newValue }
    }

    var manualUpstreamProxyProtocol: NetworkUpstreamProxyProtocol {
        get { preferences?.networkManualUpstreamProxyProtocol ?? .http }
        set { preferences?.networkManualUpstreamProxyProtocol = newValue }
    }

    var manualUpstreamProxyHost: String {
        get { preferences?.networkManualUpstreamProxyHost ?? "" }
        set { preferences?.networkManualUpstreamProxyHost = newValue }
    }

    var manualUpstreamProxyPortText: String {
        get { "\(preferences?.networkManualUpstreamProxyPort ?? 6_152)" }
        set {
            let filtered = newValue.filter(\.isNumber)
            preferences?.networkManualUpstreamProxyPort = min(max(Int(filtered) ?? 0, 0), 65_535)
        }
    }

    var manualUpstreamProxyPACURL: String {
        get { preferences?.networkManualUpstreamProxyPACURL ?? "" }
        set { preferences?.networkManualUpstreamProxyPACURL = newValue }
    }

    var manualUpstreamProxyUsername: String {
        get { preferences?.networkManualUpstreamProxyUsername ?? "" }
        set { preferences?.networkManualUpstreamProxyUsername = newValue }
    }

    var manualUpstreamProxyIncludeHosts: String {
        get { preferences?.networkManualUpstreamProxyIncludeHosts ?? "" }
        set { preferences?.networkManualUpstreamProxyIncludeHosts = newValue }
    }

    var manualUpstreamProxyExcludeHosts: String {
        get { preferences?.networkManualUpstreamProxyExcludeHosts ?? "" }
        set { preferences?.networkManualUpstreamProxyExcludeHosts = newValue }
    }

    var manualUpstreamBypassLocalhost: Bool {
        get { preferences?.networkManualUpstreamBypassLocalhost ?? true }
        set { preferences?.networkManualUpstreamBypassLocalhost = newValue }
    }

    var manualUpstreamDNSOverSOCKS: Bool {
        get { preferences?.networkManualUpstreamDNSOverSOCKS ?? true }
        set { preferences?.networkManualUpstreamDNSOverSOCKS = newValue }
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

    func resetTrafficFilters() {
        trafficFilter = NetworkTrafficFilter()
    }

    func togglePinnedFilter() {
        trafficFilter.pinnedOnly.toggle()
        if trafficFilter.pinnedOnly {
            trafficFilter.savedOnly = false
        }
    }

    func toggleSavedFilter() {
        trafficFilter.savedOnly.toggle()
        if trafficFilter.savedOnly {
            trafficFilter.pinnedOnly = false
        }
    }

    func toggleAppFilter(_ app: String) {
        toggle(app, in: &trafficFilter.apps)
    }

    func toggleDomainFilter(_ domain: String) {
        toggle(domain, in: &trafficFilter.domains)
    }

    func toggleMethodFilter(_ method: String) {
        toggle(method, in: &trafficFilter.methods)
    }

    func toggleStatusFilter(_ status: NetworkTrafficStatusFilter) {
        toggle(status, in: &trafficFilter.statuses)
    }

    func toggleProtocolFilter(_ proto: NetworkFlowProtocol) {
        toggle(proto, in: &trafficFilter.protocols)
    }

    func togglePinned(for id: UUID) {
        updateFlow(id: id) { $0.isPinned.toggle() }
    }

    func toggleSaved(for id: UUID) {
        updateFlow(id: id) { $0.isSaved.toggle() }
    }

    func prepareReplay(for flow: NetworkFlow) {
        replayDraft = NetworkReplayDraft(
            sourceFlowID: flow.id,
            method: flow.request.method,
            url: flow.request.url,
            headers: flow.request.headers,
            bodyText: flow.request.body.text,
            contentType: flow.request.body.contentType
        )
    }

    func cancelReplay() {
        replayDraft = nil
    }

    func performReplay() {
        guard let draft = replayDraft else { return }
        isReplayWorking = true
        Task { @MainActor in
            do {
                let flow = try await proxyBackend.replay(draft)
                flows.insert(flow, at: 0)
                selectedFlowID = flow.id
                replayDraft = nil
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
            isReplayWorking = false
        }
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
        performHelperAction(action)
    }

    func performHelperAction(_ action: NetworkHelperAction) {
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

    func refreshRules() {
        isRulesWorking = true
        Task { @MainActor in
            rules = await proxyBackend.rules()
            selectedRuleID = selectedRuleID ?? rules.first?.id
            isRulesWorking = false
        }
    }

    func createRule(kind: NetworkRuleActionKind = .block) {
        var rule = NetworkRuleDraft()
        rule.name = "New \(kind.title) Rule"
        rule.action.kind = kind
        rules.append(rule)
        selectedRuleID = rule.id
    }

    func updateSelectedRule(_ transform: (inout NetworkRuleDraft) -> Void) {
        guard let rule = selectedRule, let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        transform(&rules[index])
    }

    func saveSelectedRule() {
        guard let rule = selectedRule else { return }
        isRulesWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.saveRule(rule)
                rules = await proxyBackend.rules()
                selectedRuleID = rule.id
                ruleStatusMessage = "Saved \(rule.name)"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
            isRulesWorking = false
        }
    }

    func duplicateSelectedRule() {
        guard var rule = selectedRule else { return }
        rule.id = UUID()
        rule.name += " Copy"
        rule.isEnabled = false
        rules.append(rule)
        selectedRuleID = rule.id
    }

    func deleteSelectedRule() {
        guard let rule = selectedRule else { return }
        isRulesWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.deleteRule(id: rule.id)
                rules.removeAll { $0.id == rule.id }
                selectedRuleID = rules.first?.id
                ruleStatusMessage = "Deleted \(rule.name)"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
            isRulesWorking = false
        }
    }

    func setRuleEnabled(_ rule: NetworkRuleDraft, enabled: Bool) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled = enabled
        }
        Task { @MainActor in
            do {
                try await proxyBackend.setRuleEnabled(id: rule.id, enabled: enabled)
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func moveSelectedRuleUp() {
        moveSelectedRule(offset: -1)
    }

    func moveSelectedRuleDown() {
        moveSelectedRule(offset: 1)
    }

    func testSelectedRuleAgainstSelectedFlow() {
        guard let rule = selectedRule else { return }
        let flow = selectedFlow
        let url = flow.flatMap { URL(string: $0.request.url) } ?? URL(string: "https://example.com/")!
        let method = flow?.request.method ?? "GET"
        let headers = flow?.request.headers ?? []
        Task { @MainActor in
            ruleMatchResult = await proxyBackend.testRule(rule, sampleURL: url, method: method, headers: headers)
        }
    }

    func exportRulesToPasteboard() {
        Task { @MainActor in
            do {
                let data = try await proxyBackend.exportRulesData()
                if let text = String(data: data, encoding: .utf8) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ruleStatusMessage = "Rules copied to clipboard"
                }
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func importRulesFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8)
        else {
            ruleStatusMessage = "Clipboard does not contain rule JSON."
            return
        }
        Task { @MainActor in
            do {
                try await proxyBackend.importRulesData(data)
                rules = await proxyBackend.rules()
                ruleStatusMessage = "Imported \(rules.count) rules"
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshPlugins() {
        isPluginsWorking = true
        Task { @MainActor in
            plugins = await proxyBackend.plugins()
            isPluginsWorking = false
        }
    }

    func installPlugin(at path: String) {
        isPluginsWorking = true
        Task { @MainActor in
            do {
                try await proxyBackend.installPlugin(at: path)
                plugins = await proxyBackend.plugins()
                pluginStatusMessage = "Installed plugin"
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
            isPluginsWorking = false
        }
    }

    func setPluginEnabled(_ plugin: NetworkPluginItem, enabled: Bool) {
        Task { @MainActor in
            do {
                try await proxyBackend.setPluginEnabled(id: plugin.id, enabled: enabled)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func reloadPlugin(_ plugin: NetworkPluginItem) {
        Task { @MainActor in
            do {
                try await proxyBackend.reloadPlugin(id: plugin.id)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func deletePlugin(_ plugin: NetworkPluginItem) {
        Task { @MainActor in
            do {
                try await proxyBackend.deletePlugin(id: plugin.id)
                plugins = await proxyBackend.plugins()
            } catch {
                pluginStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshBreakpoints() {
        Task { @MainActor in
            breakpoints = await proxyBackend.breakpoints()
            selectedBreakpointID = selectedBreakpointID ?? breakpoints.first?.id
        }
    }

    func updateBreakpoint(_ item: NetworkBreakpointItem) {
        if let index = breakpoints.firstIndex(where: { $0.id == item.id }) {
            breakpoints[index] = item
        }
        Task { @MainActor in
            await proxyBackend.updateBreakpoint(item)
        }
    }

    func resolveBreakpoint(_ item: NetworkBreakpointItem, decision: NetworkBreakpointDecision) {
        Task { @MainActor in
            await proxyBackend.resolveBreakpoint(id: item.id, decision: decision)
            breakpoints = await proxyBackend.breakpoints()
            selectedBreakpointID = breakpoints.first?.id
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
        Task { @MainActor in
            do {
                let handoff = try await upstreamProxySettingsBeforeSystemProxy(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered
                )
                if let confirmation = handoff.confirmation {
                    upstreamProxyConfirmation = confirmation
                    isSystemProxyWorking = false
                    return
                }
                try await applyUpstreamAndEnableSystemProxy(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered,
                    settings: handoff.settings
                )
            } catch {
                systemProxyStatus.lastError = error.localizedDescription
                isSystemProxyWorking = false
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

    func confirmUpstreamProxyChaining() {
        guard let confirmation = upstreamProxyConfirmation else { return }
        upstreamProxyConfirmation = nil
        isSystemProxyWorking = true
        Task { @MainActor in
            do {
                try await applyUpstreamAndEnableSystemProxy(
                    endpoint: confirmation.endpoint,
                    autoTriggered: confirmation.autoTriggered,
                    settings: confirmation.settings
                )
            } catch {
                systemProxyStatus.lastError = error.localizedDescription
                isSystemProxyWorking = false
            }
        }
    }

    func cancelUpstreamProxyChaining() {
        upstreamProxyConfirmation = nil
        upstreamProxyStatusMessage = "Existing system proxy was left unchanged."
        isSystemProxyWorking = false
    }

    func testUpstreamProxy() {
        upstreamProxyTestResult = nil
        upstreamProxyStatusMessage = nil
        isUpstreamProxyWorking = true
        Task { @MainActor in
            do {
                let endpoint = listeningEndpoint ?? NetworkProxyEndpoint(host: "127.0.0.1", port: 9_090)
                let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
                let result = await proxyBackend.testUpstreamProxy(settings)
                upstreamProxyTestResult = result
                upstreamProxyStatusMessage = result.errorMessage ?? result.routeSummary
            } catch {
                upstreamProxyTestResult = NetworkUpstreamProxyTestResult(
                    isReachable: false,
                    routeSummary: "Failed",
                    errorMessage: error.localizedDescription
                )
                upstreamProxyStatusMessage = error.localizedDescription
            }
            isUpstreamProxyWorking = false
        }
    }

    func applyCurrentUpstreamProxy() {
        upstreamProxyTestResult = nil
        upstreamProxyStatusMessage = nil
        isUpstreamProxyWorking = true
        Task { @MainActor in
            do {
                let endpoint = listeningEndpoint ?? NetworkProxyEndpoint(host: "127.0.0.1", port: 9_090)
                let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
                await proxyBackend.updateUpstreamProxy(settings)
                systemProxyStatus.upstreamProxySummary = settings.isEnabled ? settings.summary : nil
                upstreamProxyStatusMessage = settings.isEnabled
                    ? "Applied upstream: \(settings.summary)"
                    : "Upstream disabled. Rockxy will connect directly."
            } catch {
                upstreamProxyStatusMessage = error.localizedDescription
            }
            isUpstreamProxyWorking = false
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

    private func matchesTrafficFilter(_ flow: NetworkFlow) -> Bool {
        if trafficFilter.pinnedOnly, !flow.isPinned { return false }
        if trafficFilter.savedOnly, !flow.isSaved { return false }
        if !trafficFilter.protocols.isEmpty, !trafficFilter.protocols.contains(flow.flowProtocol) { return false }
        if !trafficFilter.apps.isEmpty, !trafficFilter.apps.contains(flow.clientName.isEmpty ? "Unknown" : flow.clientName) { return false }
        if !trafficFilter.domains.isEmpty, !trafficFilter.domains.contains(flow.domainDisplay) { return false }
        if !trafficFilter.methods.isEmpty, !trafficFilter.methods.contains(flow.methodDisplay) { return false }
        if !trafficFilter.statuses.isEmpty, !trafficFilter.statuses.contains(where: { $0.matches(flow) }) { return false }

        let query = trafficFilter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return flow.request.url.localizedCaseInsensitiveContains(query)
            || flow.request.method.localizedCaseInsensitiveContains(query)
            || flow.clientName.localizedCaseInsensitiveContains(query)
            || flow.statusDisplay.localizedCaseInsensitiveContains(query)
            || flow.domainDisplay.localizedCaseInsensitiveContains(query)
            || (flow.matchedRuleName?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func groupedFilters(_ values: [String], symbol: String) -> [NetworkTrafficFilterGroup] {
        let counts = Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .mapValues(\.count)
        return counts
            .map { NetworkTrafficFilterGroup(id: $0.key, title: $0.key, symbol: symbol, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func updateFlow(id: UUID, _ transform: (inout NetworkFlow) -> Void) {
        guard let index = flows.firstIndex(where: { $0.id == id }) else { return }
        transform(&flows[index])
    }

    private func moveSelectedRule(offset: Int) {
        guard let selectedRuleID,
              let source = rules.firstIndex(where: { $0.id == selectedRuleID })
        else { return }
        let destination = max(0, min(rules.count - 1, source + offset))
        guard source != destination else { return }
        let rule = rules.remove(at: source)
        rules.insert(rule, at: destination)
        for index in rules.indices {
            rules[index].priority = index
        }
        Task { @MainActor in
            let nextID = destination + 1 < rules.count ? rules[destination + 1].id : nil
            do {
                try await proxyBackend.moveRule(id: selectedRuleID, before: nextID)
            } catch {
                ruleStatusMessage = error.localizedDescription
            }
        }
    }

    private func upstreamProxySettingsBeforeSystemProxy(
        endpoint: NetworkProxyEndpoint,
        autoTriggered: Bool
    ) async throws -> (settings: NetworkUpstreamProxySettings, confirmation: NetworkUpstreamProxyConfirmation?) {
        let settings = try await resolvedUpstreamProxySettings(endpoint: endpoint)
        if upstreamProxyMode == .automatic,
           askBeforeChainingExistingSystemProxy,
           settings.isEnabled
        {
            return (
                settings,
                NetworkUpstreamProxyConfirmation(
                    endpoint: endpoint,
                    autoTriggered: autoTriggered,
                    settings: settings
                )
            )
        }
        return (settings, nil)
    }

    private func applyUpstreamAndEnableSystemProxy(
        endpoint: NetworkProxyEndpoint,
        autoTriggered: Bool,
        settings: NetworkUpstreamProxySettings
    ) async throws {
        await proxyBackend.updateUpstreamProxy(settings)
        var status = try await systemProxyService.enable(endpoint: endpoint)
        status.upstreamProxySummary = settings.isEnabled ? settings.summary : nil
        systemProxyStatus = status
        upstreamProxyStatusMessage = settings.isEnabled
            ? "Chaining through \(settings.summary)"
            : "No upstream proxy detected"
        if autoTriggered, status.isEnabled {
            autoEnabledSystemProxyForCurrentCapture = true
        }
        isSystemProxyWorking = false
    }

    private func resolvedUpstreamProxySettings(endpoint: NetworkProxyEndpoint) async throws -> NetworkUpstreamProxySettings {
        switch upstreamProxyMode {
        case .off:
            return .disabled
        case .manual:
            return try await Self.loadPACScriptIfNeeded(manualUpstreamProxySettings())
        case .automatic:
            guard let detected = try await systemProxyService.detectedUpstreamProxy(excluding: endpoint) else {
                return .disabled
            }
            return try await Self.loadPACScriptIfNeeded(detected)
        }
    }

    private func manualUpstreamProxySettings() -> NetworkUpstreamProxySettings {
        let proto = manualUpstreamProxyProtocol
        let includeHosts = Self.hostPatternList(from: manualUpstreamProxyIncludeHosts)
        let excludeHosts = Self.hostPatternList(from: manualUpstreamProxyExcludeHosts)
        let portValue = preferences?.networkManualUpstreamProxyPort ?? 0
        let port = UInt16(exactly: portValue)
        let trimmedHost = manualUpstreamProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPACURL = manualUpstreamProxyPACURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if proto == .pac {
            guard let url = URL(string: trimmedPACURL), !trimmedPACURL.isEmpty else {
                return .disabled
            }
            return NetworkUpstreamProxySettings(
                isEnabled: true,
                proxies: [
                    NetworkUpstreamProxyServerSettings(
                        proto: .pac,
                        host: "",
                        port: 0,
                        pacURL: url
                    ),
                ],
                includeHosts: includeHosts,
                excludeHosts: excludeHosts,
                bypassLocalhost: manualUpstreamBypassLocalhost,
                dnsOverSocks: manualUpstreamDNSOverSOCKS
            )
        }

        guard !trimmedHost.isEmpty, let port else {
            return .disabled
        }

        return NetworkUpstreamProxySettings(
            isEnabled: true,
            proxies: [
                NetworkUpstreamProxyServerSettings(
                    proto: proto,
                    host: trimmedHost,
                    port: port,
                    username: manualUpstreamProxyUsername.nilIfBlank,
                    password: manualUpstreamProxyPassword.nilIfBlank
                ),
            ],
            includeHosts: includeHosts,
            excludeHosts: excludeHosts,
            bypassLocalhost: manualUpstreamBypassLocalhost,
            dnsOverSocks: manualUpstreamDNSOverSOCKS
        )
    }

    private static func hostPatternList(from text: String) -> [String] {
        text
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func loadPACScriptIfNeeded(_ settings: NetworkUpstreamProxySettings) async throws -> NetworkUpstreamProxySettings {
        var settings = settings
        for index in settings.proxies.indices where settings.proxies[index].proto == .pac {
            guard settings.proxies[index].pacScript?.isEmpty != false,
                  let url = settings.proxies[index].pacURL
            else { continue }
            settings.proxies[index].pacScript = try await Task.detached(priority: .utility) {
                if url.isFileURL {
                    return try String(contentsOf: url, encoding: .utf8)
                }
                let data = try Data(contentsOf: url)
                return String(data: data, encoding: .utf8) ?? ""
            }.value
        }
        return settings
    }

    static func helperState(from snapshot: RockxyHelperSnapshot) -> NetworkHelperState {
        NetworkHelperState(
            statusID: snapshot.status.rawValue,
            statusMessage: snapshot.statusMessage,
            detailMessage: snapshot.lastErrorMessage,
            action: snapshot.action.map(NetworkHelperAction.init),
            isReachable: snapshot.isReachable,
            canUsePrivilegedHelper: snapshot.canUsePrivilegedHelper,
            registrationStatus: snapshot.registrationStatus,
            installedVersion: snapshot.installedVersion,
            installedBuild: snapshot.installedBuild,
            installedProtocolVersion: snapshot.installedProtocolVersion,
            bundledVersion: snapshot.bundledVersion,
            bundledBuild: snapshot.bundledBuild,
            expectedProtocolVersion: snapshot.expectedProtocolVersion
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
