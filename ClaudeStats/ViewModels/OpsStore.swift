import Darwin
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class OpsStore {
    private let service: any OpsServicing

    var ports: [OpsPortItem] = []
    var processes: [OpsProcessItem] = []
    var brewSnapshot: OpsBrewSnapshot = .missing
    var environmentTools: [OpsEnvironmentTool] = []
    var cleanupItems: [OpsCleanupItem] = []
    var diagnostics = OpsDiagnosticsSnapshot(proxySummary: "Not loaded.", dnsSummary: "Not loaded.", hostsEntries: [])
    var urlDiagnosticResult: OpsURLDiagnosticResult?

    var selectedPortID: String?
    var selectedProcessID: Int32?
    var selectedBrewPackageID: OpsBrewPackage.ID?
    var selectedCleanupKinds: Set<OpsCleanupKind> = []

    var portQuery = ""
    var processQuery = ""
    var brewQuery = ""
    var urlInput = ""
    var processSort: OpsProcessSort = .developer
    var pendingConfirmation: OpsConfirmation?
    var lastError: String?
    var lastActionOutput: String?

    private var loadedSections: Set<OpsSection> = []
    private var loadingSections: Set<OpsSection> = []
    private var queuedRefreshSections: Set<OpsSection> = []
    private var workingActions: Set<String> = []
    private var urlDiagnosticsTask: Task<Void, Never>?
    private var latestURLDiagnosticsID: UUID?

    init(service: any OpsServicing = OpsService()) {
        self.service = service
    }

    var isWorking: Bool {
        !workingActions.isEmpty
    }

    var canRunAction: Bool {
        !isWorking && pendingConfirmation == nil
    }

    func isLoading(_ section: OpsSection) -> Bool {
        loadingSections.contains(section)
    }

    func loadIfNeeded(_ section: OpsSection) {
        guard !loadedSections.contains(section) else { return }
        refresh(section)
    }

    func refresh(_ section: OpsSection, force: Bool = false) {
        if loadingSections.contains(section) {
            if force { queuedRefreshSections.insert(section) }
            return
        }
        loadingSections.insert(section)
        Task {
            do {
                switch section {
                case .ports:
                    ports = try await service.loadPorts()
                    keepPortSelectionValid()
                case .processes:
                    processes = try await service.loadProcesses()
                    keepProcessSelectionValid()
                case .brew:
                    brewSnapshot = await service.loadBrew()
                    keepBrewSelectionValid()
                case .environment:
                    environmentTools = await service.loadEnvironment()
                case .cleanup:
                    cleanupItems = await service.loadCleanupItems()
                    selectedCleanupKinds.formIntersection(Set(cleanupItems.filter(\.isActionable).map(\.kind)))
                case .diagnostics:
                    diagnostics = await service.loadDiagnostics()
                }
                loadedSections.insert(section)
            } catch {
                setError(error)
            }
            loadingSections.remove(section)
            if queuedRefreshSections.remove(section) != nil {
                refresh(section, force: true)
            }
        }
    }

    var filteredPorts: [OpsPortItem] {
        let query = portQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ports }
        return ports.filter { item in
            item.processName.localizedCaseInsensitiveContains(query)
                || item.user.localizedCaseInsensitiveContains(query)
                || "\(item.port)".contains(query)
                || item.commandLine.localizedCaseInsensitiveContains(query)
                || item.localAddress.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedPort: OpsPortItem? {
        if let selectedPortID,
           let match = filteredPorts.first(where: { $0.id == selectedPortID }) {
            return match
        }
        return filteredPorts.first
    }

    var filteredProcesses: [OpsProcessItem] {
        let query = processQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? processes : processes.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.user.localizedCaseInsensitiveContains(query)
                || "\(item.pid)".contains(query)
                || item.commandLine.localizedCaseInsensitiveContains(query)
        }

        return matches.sorted { left, right in
            switch processSort {
            case .developer:
                if left.isDeveloperProcess != right.isDeveloperProcess { return left.isDeveloperProcess && !right.isDeveloperProcess }
                if left.cpuPercent != right.cpuPercent { return left.cpuPercent > right.cpuPercent }
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            case .cpu:
                if left.cpuPercent != right.cpuPercent { return left.cpuPercent > right.cpuPercent }
                return left.displayName < right.displayName
            case .memory:
                if left.memoryPercent != right.memoryPercent { return left.memoryPercent > right.memoryPercent }
                return left.displayName < right.displayName
            case .name:
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
        }
    }

    var selectedProcess: OpsProcessItem? {
        if let selectedProcessID,
           let match = filteredProcesses.first(where: { $0.pid == selectedProcessID }) {
            return match
        }
        return filteredProcesses.first
    }

    var filteredBrewPackages: [OpsBrewPackage] {
        let query = brewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return brewSnapshot.packages }
        return brewSnapshot.packages.filter { package in
            package.name.localizedCaseInsensitiveContains(query)
                || package.installedVersion.localizedCaseInsensitiveContains(query)
                || (package.latestVersion?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedBrewPackage: OpsBrewPackage? {
        if let selectedBrewPackageID,
           let match = brewSnapshot.packages.first(where: { $0.id == selectedBrewPackageID }) {
            return match
        }
        return filteredBrewPackages.first
    }

    var selectedCleanupItems: [OpsCleanupItem] {
        cleanupItems.filter { selectedCleanupKinds.contains($0.kind) }
    }

    func selectPort(_ item: OpsPortItem) {
        selectedPortID = item.id
    }

    func selectProcess(_ item: OpsProcessItem) {
        selectedProcessID = item.pid
    }

    func selectBrewPackage(_ item: OpsBrewPackage) {
        selectedBrewPackageID = item.id
    }

    func toggleCleanupSelection(_ item: OpsCleanupItem) {
        guard item.isActionable else { return }
        if selectedCleanupKinds.contains(item.kind) {
            selectedCleanupKinds.remove(item.kind)
        } else {
            selectedCleanupKinds.insert(item.kind)
        }
    }

    func clearError() {
        lastError = nil
    }

    func clearActionOutput() {
        lastActionOutput = nil
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func requestTerminate(_ process: OpsProcessItem) {
        requestTerminate(pid: process.pid, displayName: process.displayName, identity: process.identity, protection: process.protection)
    }

    func requestTerminate(_ port: OpsPortItem) {
        requestTerminate(pid: port.pid, displayName: "\(port.processName) on :\(port.port)", identity: port.processIdentity, protection: port.protection)
    }

    func requestBrewInstall(_ rawName: String) {
        guard canRunAction else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            lastError = "Enter a package name first."
            return
        }
        pendingConfirmation = OpsConfirmation(
            title: "Install \(name)?",
            message: "Homebrew will download and install this package.",
            commandSummary: "brew install \(name)",
            action: .brew(.install(name))
        )
    }

    func requestBrewUninstall(_ package: OpsBrewPackage) {
        guard canRunAction else { return }
        pendingConfirmation = OpsConfirmation(
            title: "Uninstall \(package.name)?",
            message: "Homebrew will remove this package. Other packages that depend on it may be affected.",
            commandSummary: "brew uninstall \(package.name)",
            action: .brew(.uninstall(package.name))
        )
    }

    func requestBrewUpgrade(_ package: OpsBrewPackage) {
        guard canRunAction else { return }
        pendingConfirmation = OpsConfirmation(
            title: "Upgrade \(package.name)?",
            message: "Homebrew will upgrade the selected package.",
            commandSummary: "brew upgrade \(package.name)",
            action: .brew(.upgrade(package.name))
        )
    }

    func requestBrewCleanup() {
        guard canRunAction else { return }
        pendingConfirmation = OpsConfirmation(
            title: "Run brew cleanup?",
            message: "Homebrew will remove old downloads and stale package versions.",
            commandSummary: "brew cleanup",
            action: .brew(.cleanup)
        )
    }

    func requestBrewService(_ serviceName: String, action: String) {
        guard canRunAction,
              let serviceAction = OpsBrewServiceAction(rawValue: action) else { return }
        pendingConfirmation = OpsConfirmation(
            title: "\(action.capitalized) \(serviceName)?",
            message: "Homebrew services will \(action) this service for the current user.",
            commandSummary: "brew services \(action) \(serviceName)",
            action: .brew(.service(serviceAction, serviceName))
        )
    }

    func requestCleanupSelected() {
        guard canRunAction else { return }
        let kinds = selectedCleanupKinds
        guard !kinds.isEmpty else {
            lastError = "Select at least one cleanup target."
            return
        }
        let names = cleanupItems
            .filter { kinds.contains($0.kind) }
            .map { $0.kind.title }
            .joined(separator: ", ")
        pendingConfirmation = OpsConfirmation(
            title: "Clean selected caches?",
            message: "This will remove: \(names). These caches can be rebuilt, but future builds or installs may take longer.",
            commandSummary: "Remove selected allowlisted cache paths",
            action: .cleanup(kinds: kinds)
        )
    }

    func confirmPendingAction() {
        guard !isWorking, let confirmation = pendingConfirmation else { return }
        pendingConfirmation = nil
        workingActions.insert(confirmation.id.uuidString)
        Task {
            defer { workingActions.remove(confirmation.id.uuidString) }
            do {
                switch confirmation.action {
                case .terminate(let target, let displayName, let signal):
                    let outcome = try await service.terminate(target: target, signal: signal)
                    if outcome.isStillRunning && signal == SIGTERM {
                        pendingConfirmation = OpsConfirmation(
                            title: "Force quit \(displayName)?",
                            message: "The process is still running after SIGTERM. SIGKILL cannot be handled by the process.",
                            commandSummary: "kill -KILL \(target.pid)",
                            action: .terminate(target: target, displayName: displayName, signal: SIGKILL)
                        )
                    }
                    refresh(.ports, force: true)
                    refresh(.processes, force: true)
                case .brew(let action):
                    let result = try await service.runBrew(action: action)
                    lastActionOutput = result.outputText
                    refresh(.brew, force: true)
                case .cleanup(let kinds):
                    let result = try await service.cleanup(kinds: kinds)
                    if !result.skippedKinds.isEmpty {
                        lastError = result.skippedKinds.map { "\($0.key.title): \($0.value)" }.joined(separator: "\n")
                    }
                    lastActionOutput = result.commandOutput
                    selectedCleanupKinds.subtract(result.removedKinds)
                    refresh(.cleanup, force: true)
                }
            } catch {
                setError(error)
            }
        }
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    func runURLDiagnostics() {
        guard !isWorking else { return }
        let raw = urlInput
        let requestID = UUID()
        latestURLDiagnosticsID = requestID
        urlDiagnosticsTask?.cancel()
        urlDiagnosticsTask = Task { @MainActor in
            workingActions.insert("url-diagnostics-\(requestID.uuidString)")
            defer { workingActions.remove("url-diagnostics-\(requestID.uuidString)") }
            let result = await service.runURLDiagnostics(raw)
            guard latestURLDiagnosticsID == requestID, !Task.isCancelled else { return }
            urlDiagnosticResult = result
        }
    }

    private func requestTerminate(pid: Int32, displayName: String, identity: OpsProcessIdentity, protection: OpsProtection) {
        guard canRunAction else { return }
        if let reason = protection.reason {
            lastError = "\(displayName) cannot be ended here: \(reason)"
            return
        }
        pendingConfirmation = OpsConfirmation(
            title: "End \(displayName)?",
            message: "Ops will send SIGTERM first. If the process keeps running, you can confirm a force quit next.",
            commandSummary: "kill -TERM \(pid)",
            action: .terminate(target: identity, displayName: displayName, signal: SIGTERM)
        )
    }

    private func keepPortSelectionValid() {
        if let selectedPortID, ports.contains(where: { $0.id == selectedPortID }) { return }
        selectedPortID = ports.first?.id
    }

    private func keepProcessSelectionValid() {
        if let selectedProcessID, processes.contains(where: { $0.pid == selectedProcessID }) { return }
        selectedProcessID = processes.first?.pid
    }

    private func keepBrewSelectionValid() {
        if let selectedBrewPackageID, brewSnapshot.packages.contains(where: { $0.id == selectedBrewPackageID }) { return }
        selectedBrewPackageID = brewSnapshot.packages.first?.id
    }

    private func setError(_ error: Error) {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            lastError = description
        } else {
            lastError = error.localizedDescription
        }
    }
}
