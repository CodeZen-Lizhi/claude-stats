import Foundation

enum SystemMonitorRefreshRate: String, CaseIterable, Sendable, Identifiable {
    case off
    case oneSecond
    case threeSeconds
    case tenSeconds
    case thirtySeconds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .oneSecond: "1s"
        case .threeSeconds: "3s"
        case .tenSeconds: "10s"
        case .thirtySeconds: "30s"
        }
    }

    var description: String {
        switch self {
        case .off: "Manual refresh only"
        case .oneSecond: "Realtime"
        case .threeSeconds: "Balanced"
        case .tenSeconds: "Quiet"
        case .thirtySeconds: "Low power"
        }
    }

    var interval: Duration? {
        switch self {
        case .off: nil
        case .oneSecond: .seconds(1)
        case .threeSeconds: .seconds(3)
        case .tenSeconds: .seconds(10)
        case .thirtySeconds: .seconds(30)
        }
    }
}

enum SystemMonitorModule: String, CaseIterable, Sendable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case gpu
    case thermal

    static let defaultVisible: Set<SystemMonitorModule> = Set(allCases)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .gpu: "GPU"
        case .thermal: "Thermal"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75percent"
        case .gpu: "display"
        case .thermal: "thermometer.medium"
        }
    }

    var settingsDescription: String {
        switch self {
        case .cpu: "Processor utilization and per-core load."
        case .memory: "Memory pressure, active, wired, compressed, and swap."
        case .disk: "System volume capacity plus read/write activity."
        case .network: "Physical interface upload/download throughput."
        case .battery: "Battery level, health, charge state, and adapter power."
        case .gpu: "Read-only GPU utilization and temperature when available."
        case .thermal: "macOS thermal pressure state."
        }
    }
}
