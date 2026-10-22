import Darwin
import Foundation
import IOKit.ps

/// Live system numbers for Performance and the menu bar monitor.
public struct MemoryUsage: Sendable {
    public let total: UInt64
    public let used: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct BatteryStatus: Sendable {
    public let level: Double
    public let isCharging: Bool
}

public struct ProcessUsage: Identifiable, Sendable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let cpu: Double
    public let memory: UInt64
    public let command: String
    public var name: String { (command as NSString).lastPathComponent }
}

public enum SystemMetrics {
    public static func memory() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let used = active + wired + compressed - min(active, speculative + purgeable)
        return MemoryUsage(total: ProcessInfo.processInfo.physicalMemory, used: used, wired: wired, compressed: compressed)
    }

    /// Ticks of all CPU cores, used to compute usage between two samples.
    public struct CPUTicks: Sendable {
        let busy: UInt64
        let total: UInt64
    }

    public static func cpuTicks() -> CPUTicks? {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for cpu in 0..<Int(processorCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    /// CPU usage 0...1 between two samples.
    public static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double {
        let total = new.total &- old.total
        guard total > 0 else { return 0 }
        return Double(new.busy &- old.busy) / Double(total)
    }

    /// Bytes received and sent on all physical interfaces since boot.
    public static func networkBytes() -> (received: UInt64, sent: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: entry.pointee.ifa_name)
            guard entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    public static func battery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryStatus(level: Double(current) / Double(max), isCharging: (description[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }

    /// Processes sorted by CPU, from `ps`.
    public static func processes() -> [ProcessUsage] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return parseProcesses(text)
    }

    static func parseProcesses(_ text: String) -> [ProcessUsage] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = UInt64(parts[2]) else { return nil }
            return ProcessUsage(pid: pid, cpu: cpu, memory: rss * 1024, command: String(parts[3]))
        }
        .sorted { $0.cpu > $1.cpu }
    }
}
