import AppKit
import Darwin
import QuartzCore
import Foundation
import IOKit

/// CPU, memory, disk, network and battery health, sampled every two seconds while
/// something in the island is showing them.
@MainActor
final class SystemStats: ObservableObject {
    struct Snapshot: Equatable {
        var cpu: Double = 0
        var memoryUsed: UInt64 = 0
        var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
        var diskFree: Int64 = 0
        var diskTotal: Int64 = 0
        /// Bytes per second across Wi-Fi and Ethernet.
        var download: Double = 0
        var upload: Double = 0
        var batteryHealth: Int?
        var cycleCount: Int?
        var uptime: TimeInterval = 0
        var thermal: ProcessInfo.ThermalState = .nominal

        var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
        var diskUsedFraction: Double { diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0 }
    }

    @Published private(set) var snapshot = Snapshot()

    private var viewers = 0
    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastBytes: (down: UInt64, up: UInt64, at: Date)?
    private var samples = 0

    /// Each view that shows stats calls this on appear and `stopWatching` on disappear.
    func startWatching() {
        viewers += 1
        guard viewers == 1 else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stopWatching() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastBytes = nil
        samples = 0
    }

    private func sample() {
        defer { samples += 1 }
        var next = snapshot
        if let cpu = cpuUsage() { next.cpu = cpu }
        next.memoryUsed = Self.memoryUsed()
        if let disk = Self.disk() {
            next.diskFree = disk.free
            next.diskTotal = disk.total
        }
        if let rates = networkRates() {
            next.download = rates.down
            next.upload = rates.up
        }
        // Battery health barely changes; read it once a minute.
        if samples % 30 == 0 {
            let battery = Self.batteryHealth()
            next.batteryHealth = battery.health
            next.cycleCount = battery.cycles
        }
        next.uptime = ProcessInfo.processInfo.systemUptime
        next.thermal = ProcessInfo.processInfo.thermalState
        if next != snapshot { snapshot = next }
    }

    // MARK: CPU

    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return nil }
        return Double(busy - last.busy) / Double(total - last.total)
    }

    // MARK: Memory and disk

    /// Memory used the way Activity Monitor counts it: app memory, wired and compressed.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func disk() -> (free: Int64, total: Int64)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    // MARK: Network

    private func networkRates() -> (down: Double, up: Double)? {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") {
                    let counters = data.assumingMemoryBound(to: if_data.self).pointee
                    down += UInt64(counters.ifi_ibytes)
                    up += UInt64(counters.ifi_obytes)
                }
            }
            cursor = interface.ifa_next
        }
        let now = Date()
        defer { lastBytes = (down, up, now) }
        guard let last = lastBytes else { return nil }
        let seconds = now.timeIntervalSince(last.at)
        guard seconds > 0.2 else { return nil }
        // The counters are 32-bit and wrap; a wrap reads as a dip, so treat it as no data.
        let downDelta = down >= last.down ? Double(down - last.down) : 0
        let upDelta = up >= last.up ? Double(up - last.up) : 0
        return (downDelta / seconds, upDelta / seconds)
    }

    // MARK: Battery

    private static func batteryHealth() -> (health: Int?, cycles: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        let cycles = number("CycleCount")
        var health: Int?
        if let maximum = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"),
           let design = number("DesignCapacity"), design > 0 {
            health = min(100, Int((Double(maximum) / Double(design) * 100).rounded()))
        }
        return (health, cycles)
    }

    // MARK: Formatting

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1_000 { return "\(Int(bytesPerSecond)) B/s" }
        if bytesPerSecond < 1_000_000 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
    }

    static func gigabytes(_ value: UInt64) -> String {
        String(format: "%.1f GB", Double(value) / 1_073_741_824)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h \(Int(seconds) % 3600 / 60)m"
    }
}

/// Frames per second the display is drawing, counted from a display link, and the
/// most it can show (120 on ProMotion screens, 60 on others).
@MainActor
final class FPSMeter: NSObject, ObservableObject {
    @Published private(set) var fps: Int = 0
    @Published private(set) var maximum: Int = NSScreen.main?.maximumFramesPerSecond ?? 60

    private var link: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    private var viewers = 0

    func startWatching() {
        viewers += 1
        guard viewers == 1, let screen = NSScreen.main else { return }
        maximum = screen.maximumFramesPerSecond
        frames = 0
        windowStart = CACurrentMediaTime()
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopWatching() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        frames += 1
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 0.5 else { return }
        let measured = min(maximum, Int((Double(frames) / elapsed).rounded()))
        if measured != fps { fps = measured }
        frames = 0
        windowStart = now
    }
}
