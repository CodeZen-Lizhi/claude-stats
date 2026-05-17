import Foundation

struct SystemCPUCounter: Sendable, Equatable {
    var user: UInt64
    var system: UInt64
    var nice: UInt64
    var idle: UInt64

    var active: UInt64 { user + system + nice }
    var total: UInt64 { active + idle }
}

struct SystemCPULoad: Sendable, Equatable {
    var user: Double
    var system: Double
    var idle: Double

    var total: Double { user + system }
}

struct SystemByteCounter: Sendable, Equatable {
    var read: UInt64
    var write: UInt64
}

enum SystemMonitorMath {
    static func ratio(_ value: UInt64, _ total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    static func ratio(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    static func byteRate(current: UInt64, previous: UInt64?, elapsed: TimeInterval) -> Double {
        guard let previous, elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    static func cpuLoad(current: SystemCPUCounter, previous: SystemCPUCounter?) -> SystemCPULoad {
        let delta: SystemCPUCounter
        if let previous, current.total >= previous.total {
            delta = SystemCPUCounter(
                user: current.user >= previous.user ? current.user - previous.user : 0,
                system: current.system >= previous.system ? current.system - previous.system : 0,
                nice: current.nice >= previous.nice ? current.nice - previous.nice : 0,
                idle: current.idle >= previous.idle ? current.idle - previous.idle : 0
            )
        } else {
            delta = current
        }

        let total = Double(delta.total)
        guard total > 0 else {
            return SystemCPULoad(user: 0, system: 0, idle: 1)
        }

        let user = Double(delta.user + delta.nice) / total
        let system = Double(delta.system) / total
        let idle = Double(delta.idle) / total
        return SystemCPULoad(
            user: min(1, max(0, user)),
            system: min(1, max(0, system)),
            idle: min(1, max(0, idle))
        )
    }

    static func limitedHistory<T>(_ values: [T], appending value: T, limit: Int) -> [T] {
        guard limit > 0 else { return [] }
        var next = values
        next.append(value)
        if next.count > limit {
            next.removeFirst(next.count - limit)
        }
        return next
    }
}
