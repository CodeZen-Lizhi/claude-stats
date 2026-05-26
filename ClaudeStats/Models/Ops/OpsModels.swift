import Foundation

enum OpsSection: String, CaseIterable, Identifiable, Sendable, Hashable {
    case brew
    case environment

    var id: String { rawValue }

    init(storedRawValue: String) {
        self = OpsSection(rawValue: storedRawValue) ?? .brew
    }

    var title: String {
        switch self {
        case .brew: "Brew"
        case .environment: "Environment"
        }
    }

    var symbol: String {
        switch self {
        case .brew: "shippingbox"
        case .environment: "terminal"
        }
    }

    var detailTitle: String {
        switch self {
        case .brew: "Homebrew"
        case .environment: "Environment"
        }
    }

    var detailDescription: String {
        switch self {
        case .brew:
            "Review installed packages, outdated formulae, services, and doctor output."
        case .environment:
            "Check common developer tools, resolved paths, and installed versions."
        }
    }
}

enum OpsBrewPackageKind: String, Sendable, Hashable {
    case formula
    case cask
}

struct OpsBrewPackage: Identifiable, Sendable, Hashable {
    var id: String { "\(kind.rawValue):\(name)" }
    var name: String
    var installedVersion: String
    var latestVersion: String?
    var kind: OpsBrewPackageKind

    var isOutdated: Bool {
        guard let latestVersion, !latestVersion.isEmpty else { return false }
        return latestVersion != installedVersion
    }
}

struct OpsBrewServiceItem: Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var status: String
    var user: String
    var file: String?
}

struct OpsBrewSnapshot: Sendable, Hashable {
    var brewPath: String?
    var packages: [OpsBrewPackage]
    var services: [OpsBrewServiceItem]
    var doctorOutput: String
    var errors: [String] = []

    static let missing = OpsBrewSnapshot(
        brewPath: nil,
        packages: [],
        services: [],
        doctorOutput: "Homebrew was not found in /opt/homebrew/bin, /usr/local/bin, or PATH.",
        errors: ["Homebrew was not found in a trusted location."]
    )
}

enum OpsEnvironmentStatus: Sendable, Hashable {
    case available
    case missing
    case error(String)

    var title: String {
        switch self {
        case .available: "Available"
        case .missing: "Missing"
        case .error: "Error"
        }
    }
}

struct OpsEnvironmentTool: Identifiable, Sendable, Hashable {
    var id: String { command }
    var name: String
    var command: String
    var resolvedPath: String?
    var version: String?
    var status: OpsEnvironmentStatus
    var detail: String?
    var isTrustedPath: Bool
}

enum OpsPendingAction: Sendable, Hashable {
    case brew(OpsBrewAction)
}

enum OpsBrewServiceAction: String, CaseIterable, Identifiable, Sendable, Hashable {
    case start
    case stop
    case restart

    var id: String { rawValue }
}

enum OpsBrewAction: Sendable, Hashable {
    case install(String)
    case uninstall(String)
    case upgrade(String)
    case service(OpsBrewServiceAction, String)

    var arguments: [String] {
        switch self {
        case .install(let token):
            ["install", token]
        case .uninstall(let token):
            ["uninstall", token]
        case .upgrade(let token):
            ["upgrade", token]
        case .service(let action, let name):
            ["services", action.rawValue, name]
        }
    }

    var commandSummary: String {
        "brew \(arguments.joined(separator: " "))"
    }
}

struct OpsConfirmation: Identifiable, Sendable, Hashable {
    var id = UUID()
    var title: String
    var message: String
    var commandSummary: String
    var action: OpsPendingAction
}
