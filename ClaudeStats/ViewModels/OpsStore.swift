import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class OpsStore {
    private let service: any OpsServicing

    var brewSnapshot: OpsBrewSnapshot = .missing
    var environmentTools: [OpsEnvironmentTool] = []
    var selectedBrewPackageID: OpsBrewPackage.ID?
    var brewQuery = ""
    var pendingConfirmation: OpsConfirmation?
    var lastError: String?
    var lastActionOutput: String?

    private var loadedSections: Set<OpsSection> = []
    private var loadingSections: Set<OpsSection> = []
    private var queuedRefreshSections: Set<OpsSection> = []
    private var workingActions: Set<String> = []

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
                case .brew:
                    brewSnapshot = await service.loadBrew()
                    keepBrewSelectionValid()
                case .environment:
                    environmentTools = await service.loadEnvironment()
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

    func selectBrewPackage(_ item: OpsBrewPackage) {
        selectedBrewPackageID = item.id
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

    func confirmPendingAction() {
        guard !isWorking, let confirmation = pendingConfirmation else { return }
        pendingConfirmation = nil
        workingActions.insert(confirmation.id.uuidString)
        Task {
            defer { workingActions.remove(confirmation.id.uuidString) }
            do {
                switch confirmation.action {
                case .brew(let action):
                    let result = try await service.runBrew(action: action)
                    lastActionOutput = result.outputText
                    refresh(.brew, force: true)
                }
            } catch {
                setError(error)
            }
        }
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    private func keepBrewSelectionValid() {
        if let selectedBrewPackageID,
           brewSnapshot.packages.contains(where: { $0.id == selectedBrewPackageID }) {
            return
        }
        selectedBrewPackageID = filteredBrewPackages.first?.id
    }

    private func setError(_ error: Error) {
        lastError = error.localizedDescription
    }
}
