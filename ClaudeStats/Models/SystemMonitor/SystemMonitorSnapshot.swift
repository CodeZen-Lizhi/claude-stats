import Foundation

struct SystemMonitorSnapshot: Sendable, Equatable {
    var timestamp: Date
    var cpu: SystemCPUSnapshot
    var memory: SystemMemorySnapshot
    var disk: SystemDiskSnapshot
    var network: SystemNetworkSnapshot
    var battery: SystemBatterySnapshot
    var gpu: SystemGPUSnapshot
    var thermal: SystemThermalSnapshot

    static let placeholder = SystemMonitorSnapshot(
        timestamp: .now,
        cpu: .placeholder,
        memory: .placeholder,
        disk: .placeholder,
        network: .placeholder,
        battery: .placeholder,
        gpu: .unavailable,
        thermal: .init(state: .nominal)
    )
}

struct SystemCPUSnapshot: Sendable, Equatable {
    var totalUsage: Double
    var userUsage: Double
    var systemUsage: Double
    var idleUsage: Double
    var perCoreUsage: [Double]

    static let placeholder = SystemCPUSnapshot(
        totalUsage: 0,
        userUsage: 0,
        systemUsage: 0,
        idleUsage: 1,
        perCoreUsage: []
    )
}

struct SystemMemorySnapshot: Sendable, Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var activeBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var appBytes: UInt64
    var cacheBytes: UInt64
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var pressure: SystemMemoryPressure

    var usedRatio: Double { SystemMonitorMath.ratio(usedBytes, totalBytes) }
    var activeRatio: Double { SystemMonitorMath.ratio(activeBytes, totalBytes) }
    var wiredRatio: Double { SystemMonitorMath.ratio(wiredBytes, totalBytes) }
    var compressedRatio: Double { SystemMonitorMath.ratio(compressedBytes, totalBytes) }

    static let placeholder = SystemMemorySnapshot(
        totalBytes: 0,
        usedBytes: 0,
        freeBytes: 0,
        activeBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        appBytes: 0,
        cacheBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        pressure: .normal
    )
}

enum SystemMemoryPressure: String, Sendable, Equatable {
    case normal
    case warning
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }
}

struct SystemDiskSnapshot: Sendable, Equatable {
    var volumeName: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double

    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
    var usedRatio: Double { SystemMonitorMath.ratio(usedBytes, totalBytes) }

    static let placeholder = SystemDiskSnapshot(
        volumeName: "System",
        totalBytes: 0,
        freeBytes: 0,
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0
    )
}

struct SystemNetworkSnapshot: Sendable, Equatable {
    var interfaceName: String
    var displayName: String
    var isUp: Bool
    var localIPv4: String?
    var localIPv6: String?
    var uploadBytesPerSecond: Double
    var downloadBytesPerSecond: Double

    static let placeholder = SystemNetworkSnapshot(
        interfaceName: "",
        displayName: "Offline",
        isUp: false,
        localIPv4: nil,
        localIPv6: nil,
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0
    )
}

struct SystemBatterySnapshot: Sendable, Equatable {
    var isPresent: Bool
    var level: Double?
    var isCharging: Bool
    var isCharged: Bool
    var isBatteryPowered: Bool
    var powerSource: String
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var cycleCount: Int?
    var healthPercent: Int?
    var adapterWatts: Int?

    static let placeholder = SystemBatterySnapshot(
        isPresent: false,
        level: nil,
        isCharging: false,
        isCharged: false,
        isBatteryPowered: false,
        powerSource: "AC Power",
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil,
        cycleCount: nil,
        healthPercent: nil,
        adapterWatts: nil
    )
}

struct SystemGPUSnapshot: Sendable, Equatable {
    var isAvailable: Bool
    var model: String
    var utilization: Double?
    var temperatureCelsius: Double?
    var fps: Double?

    static let unavailable = SystemGPUSnapshot(
        isAvailable: false,
        model: "Unavailable",
        utilization: nil,
        temperatureCelsius: nil,
        fps: nil
    )
}

struct SystemThermalSnapshot: Sendable, Equatable {
    var state: SystemThermalState
}

enum SystemThermalState: String, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical

    var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }
}
