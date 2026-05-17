import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration
@preconcurrency import CoreWLAN

protocol SystemMonitorSampling: Sendable {
    func sample() async -> SystemMonitorSnapshot
}

actor SystemMonitorSampler: SystemMonitorSampling {
    private var previousHostCPU: SystemCPUCounter?
    private var previousCoreCPU: [SystemCPUCounter] = []
    private var previousDisk: (counter: SystemByteCounter, timestamp: Date)?
    private var previousNetwork: (interfaceName: String, counter: SystemByteCounter, timestamp: Date)?

    func sample() async -> SystemMonitorSnapshot {
        let now = Date()
        return SystemMonitorSnapshot(
            timestamp: now,
            cpu: readCPU(),
            memory: readMemory(),
            disk: readDisk(now: now),
            network: readNetwork(now: now),
            battery: readBattery(),
            gpu: readGPU(),
            thermal: readThermal()
        )
    }

    // MARK: - CPU

    private func readCPU() -> SystemCPUSnapshot {
        let hostCounter = readHostCPUCounters()
        let coreCounters = readCoreCPUCounters()

        let hostLoad = hostCounter.map { SystemMonitorMath.cpuLoad(current: $0, previous: previousHostCPU) }
            ?? SystemCPULoad(user: 0, system: 0, idle: 1)

        let previousCores = previousCoreCPU.count == coreCounters.count ? previousCoreCPU : []
        let perCore = coreCounters.enumerated().map { index, counter in
            let previous = previousCores.indices.contains(index) ? previousCores[index] : nil
            return SystemMonitorMath.cpuLoad(current: counter, previous: previous).total
        }

        previousHostCPU = hostCounter
        previousCoreCPU = coreCounters

        return SystemCPUSnapshot(
            totalUsage: hostLoad.total,
            userUsage: hostLoad.user,
            systemUsage: hostLoad.system,
            idleUsage: hostLoad.idle,
            perCoreUsage: perCore
        )
    }

    private func readHostCPUCounters() -> SystemCPUCounter? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return SystemCPUCounter(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            nice: UInt64(info.cpu_ticks.3),
            idle: UInt64(info.cpu_ticks.2)
        )
    }

    private func readCoreCPUCounters() -> [SystemCPUCounter] {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }
        defer {
            let size = vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        return (0..<Int(numCPUs)).map { index in
            let base = Int(CPU_STATE_MAX) * index
            return SystemCPUCounter(
                user: UInt64(cpuInfo[base + Int(CPU_STATE_USER)]),
                system: UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)]),
                nice: UInt64(cpuInfo[base + Int(CPU_STATE_NICE)]),
                idle: UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            )
        }
    }

    // MARK: - Memory

    private func readMemory() -> SystemMemorySnapshot {
        let total = readTotalMemoryBytes()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .placeholder }

        let pageSize = UInt64(readPageSize())
        let active = UInt64(stats.active_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize
        let grossUsed = active + inactive + speculative + wired + compressed
        let reclaimable = min(grossUsed, purgeable + external)
        let used = grossUsed - reclaimable
        let free = total > used ? total - used : 0
        let app = used > wired + compressed ? used - wired - compressed : 0

        let swap = readSwapUsage()
        return SystemMemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            appBytes: app,
            cacheBytes: purgeable + external,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: readMemoryPressure()
        )
    }

    private func readTotalMemoryBytes() -> UInt64 {
        var stats = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return ProcessInfo.processInfo.physicalMemory }
        return stats.max_mem
    }

    private func readMemoryPressure() -> SystemMemoryPressure {
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 else {
            return .unknown
        }
        switch pressureLevel {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }

    private func readPageSize() -> vm_size_t {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return vm_size_t(sysconf(_SC_PAGESIZE))
        }
        return pageSize
    }

    private func readSwapUsage() -> (total: UInt64, used: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (usage.xsu_total, usage.xsu_used)
    }

    // MARK: - Disk

    private func readDisk(now: Date) -> SystemDiskSnapshot {
        let capacity = readSystemVolumeCapacity()
        let counter = readDiskCounters()
        let elapsed = previousDisk.map { now.timeIntervalSince($0.timestamp) } ?? 0
        let readRate = SystemMonitorMath.byteRate(
            current: counter.read,
            previous: previousDisk?.counter.read,
            elapsed: elapsed
        )
        let writeRate = SystemMonitorMath.byteRate(
            current: counter.write,
            previous: previousDisk?.counter.write,
            elapsed: elapsed
        )
        previousDisk = (counter, now)
        return SystemDiskSnapshot(
            volumeName: capacity.name,
            totalBytes: capacity.total,
            freeBytes: capacity.free,
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate
        )
    }

    private func readSystemVolumeCapacity() -> (name: String, total: UInt64, free: UInt64) {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? root.resourceValues(forKeys: keys) else {
            return ("System", 0, 0)
        }
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        let freeImportant = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        let freeRegular = values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        return (values.volumeName ?? "System", total, freeImportant ?? freeRegular ?? 0)
    }

    private func readDiskCounters() -> SystemByteCounter {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return SystemByteCounter(read: 0, write: 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let properties = registryProperties(for: service),
                  let statistics = properties["Statistics"] as? [String: Any] else {
                continue
            }
            read += numericUInt64(statistics["Bytes (Read)"])
            write += numericUInt64(statistics["Bytes (Write)"])
        }
        return SystemByteCounter(read: read, write: write)
    }

    // MARK: - Network

    private func readNetwork(now: Date) -> SystemNetworkSnapshot {
        let interfaces = readNetworkInterfaces()
        guard let selected = selectNetworkInterface(from: interfaces) else {
            previousNetwork = nil
            return .placeholder
        }

        let previous = previousNetwork?.interfaceName == selected.name ? previousNetwork : nil
        let elapsed = previous.map { now.timeIntervalSince($0.timestamp) } ?? 0
        let uploadRate = SystemMonitorMath.byteRate(
            current: selected.counter.write,
            previous: previous?.counter.write,
            elapsed: elapsed
        )
        let downloadRate = SystemMonitorMath.byteRate(
            current: selected.counter.read,
            previous: previous?.counter.read,
            elapsed: elapsed
        )
        previousNetwork = (selected.name, selected.counter, now)

        return SystemNetworkSnapshot(
            interfaceName: selected.name,
            displayName: selected.displayName,
            isUp: selected.isUp,
            localIPv4: selected.localIPv4,
            localIPv6: selected.localIPv6,
            uploadBytesPerSecond: uploadRate,
            downloadBytesPerSecond: downloadRate
        )
    }

    private struct NetworkInterfaceReading {
        var name: String
        var displayName: String
        var type: String?
        var isUp: Bool
        var isLoopback: Bool
        var isVirtual: Bool
        var localIPv4: String?
        var localIPv6: String?
        var counter: SystemByteCounter
    }

    private func readNetworkInterfaces() -> [NetworkInterfaceReading] {
        let metadata = networkInterfaceMetadata()
        var readings: [String: NetworkInterfaceReading] = [:]
        var addresses: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let meta = metadata[name]
            var reading = readings[name] ?? NetworkInterfaceReading(
                name: name,
                displayName: meta?.displayName ?? name,
                type: meta?.type,
                isUp: false,
                isLoopback: false,
                isVirtual: isVirtualInterface(name),
                localIPv4: nil,
                localIPv6: nil,
                counter: SystemByteCounter(read: 0, write: 0)
            )

            reading.isUp = reading.isUp || (flags & IFF_UP) != 0
            reading.isLoopback = reading.isLoopback || (flags & IFF_LOOPBACK) != 0

            if let data = current.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                reading.counter = SystemByteCounter(
                    read: UInt64(ifData.ifi_ibytes),
                    write: UInt64(ifData.ifi_obytes)
                )
            }

            if let address = current.pointee.ifa_addr?.pointee {
                if address.sa_family == UInt8(AF_INET) {
                    reading.localIPv4 = numericAddress(from: current.pointee.ifa_addr)
                } else if address.sa_family == UInt8(AF_INET6) {
                    let value = numericAddress(from: current.pointee.ifa_addr)
                    if let value, !value.hasPrefix("fe80") {
                        reading.localIPv6 = value
                    }
                }
            }
            readings[name] = reading
        }

        return Array(readings.values)
    }

    private func networkInterfaceMetadata() -> [String: (displayName: String, type: String?)] {
        var result: [String: (displayName: String, type: String?)] = [:]
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return result }
        for item in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(item) as String? else { continue }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(item) as String? ?? bsd
            let type = SCNetworkInterfaceGetInterfaceType(item) as String?
            result[bsd] = (display, type)
        }
        return result
    }

    private func selectNetworkInterface(from interfaces: [NetworkInterfaceReading]) -> NetworkInterfaceReading? {
        let active = interfaces.filter { $0.isUp && !$0.isLoopback }
        if let wifiName = CWWiFiClient.shared().interface()?.interfaceName,
           let wifi = active.first(where: { $0.name == wifiName && !$0.isVirtual }) {
            return wifi
        }

        if let physical = active.first(where: { interface in
            !interface.isVirtual &&
                (interface.name.hasPrefix("en") ||
                 interface.type == kSCNetworkInterfaceTypeEthernet as String ||
                 interface.type == kSCNetworkInterfaceTypeIEEE80211 as String)
        }) {
            return physical
        }

        if let primary = primaryInterfaceName(),
           let match = active.first(where: { $0.name == primary && !$0.isVirtual }) {
            return match
        }

        return active.first(where: { !$0.isVirtual }) ?? active.first
    }

    private func primaryInterfaceName() -> String? {
        guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = global["PrimaryInterface"] as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func isVirtualInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") ||
            name.hasPrefix("tun") ||
            name.hasPrefix("tap") ||
            name.hasPrefix("ppp") ||
            name.hasPrefix("ipsec") ||
            name.hasPrefix("awdl") ||
            name.hasPrefix("llw")
    }

    private func numericAddress(from pointer: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let pointer else { return nil }
        var address = pointer.pointee
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            &address,
            socklen_t(address.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let end = host.firstIndex(of: 0) ?? host.endIndex
        let bytes = host[..<end].map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    // MARK: - Battery

    private func readBattery() -> SystemBatterySnapshot {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        guard let source = list.first,
              let description = IOPSGetPowerSourceDescription(psInfo, source).takeUnretainedValue() as? [String: Any] else {
            return SystemBatterySnapshot(
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
                adapterWatts: readAdapterWatts()
            )
        }

        let current = numericDouble(description[kIOPSCurrentCapacityKey])
        let maxCapacity = numericDouble(description[kIOPSMaxCapacityKey])
        let level = maxCapacity > 0 ? current / maxCapacity : nil
        let state = description[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
        let registry = readBatteryRegistryProperties()
        let designCapacity = numericDouble(registry["DesignCapacity"])
        let rawMaxCapacity = numericDouble(registry["AppleRawMaxCapacity"])
        let legacyMaxCapacity = numericDouble(registry["MaxCapacity"])
        let healthCapacity = rawMaxCapacity > 0 ? rawMaxCapacity : legacyMaxCapacity
        let health = designCapacity > 0 && healthCapacity > 0
            ? Int((healthCapacity / designCapacity * 100).rounded())
            : nil

        return SystemBatterySnapshot(
            isPresent: true,
            level: level.map { min(1, max(0, $0)) },
            isCharging: (registry["IsCharging"] as? Bool) ?? false,
            isCharged: (description[kIOPSIsChargedKey] as? Bool) ?? false,
            isBatteryPowered: state == "Battery Power",
            powerSource: state,
            timeToEmptyMinutes: positiveMinutes(description[kIOPSTimeToEmptyKey]),
            timeToFullMinutes: positiveMinutes(description[kIOPSTimeToFullChargeKey]),
            cycleCount: numericInt(registry["CycleCount"]),
            healthPercent: health,
            adapterWatts: readAdapterWatts()
        )
    }

    private func readBatteryRegistryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        return registryProperties(for: service) ?? [:]
    }

    private func readAdapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return numericInt(details[kIOPSPowerAdapterWattsKey])
    }

    private func positiveMinutes(_ value: Any?) -> Int? {
        guard let minutes = numericInt(value), minutes >= 0 else { return nil }
        return minutes
    }

    // MARK: - GPU / Thermal

    private func readGPU() -> SystemGPUSnapshot {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return .unavailable
        }
        defer { IOObjectRelease(iterator) }

        var best: SystemGPUSnapshot?
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let properties = registryProperties(for: service) else { continue }
            let stats = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
            let ioClass = properties["IOClass"] as? String ?? "GPU"
            let model = (stats["model"] as? String)
                ?? (properties["model"] as? String)
                ?? readableGPUName(from: ioClass)

            let rawUtilization = numericDouble(stats["Device Utilization %"]) > 0
                ? numericDouble(stats["Device Utilization %"])
                : numericDouble(stats["GPU Activity(%)"])
            let utilization = rawUtilization > 0 ? min(1, rawUtilization / 100) : nil
            let temperature = numericDouble(stats["Temperature(C)"]) > 0
                ? numericDouble(stats["Temperature(C)"])
                : nil

            let candidate = SystemGPUSnapshot(
                isAvailable: true,
                model: model,
                utilization: utilization,
                temperatureCelsius: temperature,
                fps: nil
            )
            if best == nil || (candidate.utilization ?? 0) > (best?.utilization ?? 0) {
                best = candidate
            }
        }

        return best ?? .unavailable
    }

    private func readableGPUName(from ioClass: String) -> String {
        let lower = ioClass.lowercased()
        if lower.contains("agx") { return "Apple Graphics" }
        if lower.contains("amd") { return "AMD Graphics" }
        if lower.contains("intel") { return "Intel Graphics" }
        if lower.contains("nvidia") { return "NVIDIA Graphics" }
        return "GPU"
    }

    private func readThermal() -> SystemThermalSnapshot {
        let state: SystemThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = .nominal
        case .fair: state = .fair
        case .serious: state = .serious
        case .critical: state = .critical
        @unknown default: state = .nominal
        }
        return SystemThermalSnapshot(state: state)
    }

    // MARK: - Helpers

    private func registryProperties(for entry: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let properties else { return nil }
        return properties.takeRetainedValue() as? [String: Any]
    }

    private func numericUInt64(_ value: Any?) -> UInt64 {
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt32 { return UInt64(value) }
        if let value = value as? UInt { return UInt64(value) }
        if let value = value as? Int64 { return UInt64(max(0, value)) }
        if let value = value as? Int { return UInt64(max(0, value)) }
        if let value = value as? NSNumber { return value.uint64Value }
        return 0
    }

    private func numericInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func numericDouble(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? UInt64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }
}
