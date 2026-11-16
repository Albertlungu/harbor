import Foundation
import HarborCore
import IOKit
import IOKit.ps

/// Ticks only while at least one view is registered, at the fastest interval any of them asked for.
@MainActor
final class SystemLoop {
    private var intervals: [UUID: TimeInterval] = [:]
    private var task: Task<Void, Never>?
    private var running: TimeInterval?
    private let tick: @MainActor () async -> Void

    init(tick: @escaping @MainActor () async -> Void) {
        self.tick = tick
    }

    func register(_ id: UUID, interval: TimeInterval) {
        intervals[id] = interval
        reschedule()
    }

    func unregister(_ id: UUID) {
        intervals[id] = nil
        reschedule()
    }

    private func reschedule() {
        guard let fastest = intervals.values.min() else {
            task?.cancel()
            task = nil
            running = nil
            return
        }
        guard fastest != running else { return }
        // A newly started loop samples at once; a faster rate only changes the cadence.
        let sampleNow = task == nil
        task?.cancel()
        running = fastest
        task = Task { [weak self] in
            if sampleNow { await self?.tick() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(fastest))
                if Task.isCancelled { break }
                await self?.tick()
            }
        }
    }
}

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var pluggedIn: Bool
    var minutesRemaining: Int?
}

/// One sampler shared by every visible monitor widget.
@MainActor
@Observable
final class SystemSampler {
    static let shared = SystemSampler()

    private(set) var cpu: Double?
    private(set) var memory: Double?
    private(set) var gpu: Double?
    private(set) var battery: BatteryInfo?
    private(set) var hasSampled = false

    @ObservationIgnored private var previousTicks: CPUTicks?
    @ObservationIgnored private var loop: SystemLoop?

    private init() {
        loop = SystemLoop { [weak self] in self?.sample() }
    }

    func register(_ id: UUID, rate: String) {
        loop?.register(id, interval: SystemLogic.interval(forRate: rate))
    }

    func unregister(_ id: UUID) {
        loop?.unregister(id)
    }

    func refresh() {
        sample()
    }

    private func sample() {
        if let ticks = Self.readCPUTicks() {
            if let previous = previousTicks {
                cpu = SystemLogic.cpuPercent(previous: previous, current: ticks)
            }
            previousTicks = ticks
        }
        memory = Self.readMemory()
        gpu = Self.readGPU()
        battery = Self.readBattery()
        hasSampled = true
    }

    // MARK: Readers

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks is indexed by CPU_STATE_USER, SYSTEM, IDLE, NICE.
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    private static func readMemory() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        return SystemLogic.memoryPercent(
            active: UInt64(stats.active_count) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            physical: ProcessInfo.processInfo.physicalMemory)
    }

    /// Nil when the driver exposes no utilization figure; it is never estimated.
    private static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let raw = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = raw as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, min(100, max(0, value)))
        }
        return best
    }

    private static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryInfo(percent: min(100, current * 100 / maximum), isCharging: charging, pluggedIn: plugged,
                               minutesRemaining: minutes.flatMap { $0 > 0 ? $0 : nil })
        }
        return nil
    }
}
