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
        case .cpu:
            L10n.string("CPU", defaultValue: "CPU")
        case .memory:
            L10n.string("Memory", defaultValue: "Memory")
        case .disk:
            L10n.string("Disk", defaultValue: "Disk")
        case .network:
            L10n.string("Network", defaultValue: "Network")
        case .battery:
            L10n.string("Power", defaultValue: "Power")
        case .gpu:
            L10n.string("GPU", defaultValue: "GPU")
        case .thermal:
            L10n.string("Thermal", defaultValue: "Thermal")
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
        case .cpu:
            L10n.string("system_monitor.module.cpu.description", defaultValue: "Processor utilization and per-core load.")
        case .memory:
            L10n.string("system_monitor.module.memory.description", defaultValue: "Memory pressure, active, wired, compressed, and swap.")
        case .disk:
            L10n.string("system_monitor.module.disk.description", defaultValue: "System volume capacity plus read/write activity.")
        case .network:
            L10n.string("system_monitor.module.network.description", defaultValue: "Physical interface upload/download throughput.")
        case .battery:
            L10n.string("system_monitor.module.power.description", defaultValue: "Battery level, health, charge state, and adapter power.")
        case .gpu:
            L10n.string("system_monitor.module.gpu.description", defaultValue: "Read-only GPU utilization and temperature when available.")
        case .thermal:
            L10n.string("system_monitor.module.thermal.description", defaultValue: "macOS thermal pressure state.")
        }
    }
}
