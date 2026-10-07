import Darwin
import Foundation

/// CPU and memory statistics from the Mach host APIs.
///
/// Sampling only happens while a System Stats view is on screen: each view
/// calls `beginSampling()` on appear and `endSampling()` on disappear, and the
/// 2-second timer stops completely when nothing is showing (e.g. the notch is
/// collapsed).
@Observable
@MainActor
final class SystemStatsService {
    static let shared = SystemStatsService()

    enum Pressure: String { case normal = "Normal", warning = "Warning", critical = "Critical" }

    /// 0...1 across all cores.
    private(set) var cpuUsage: Double = 0
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private(set) var pressure: Pressure = .normal

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previousTicks: (used: UInt64, total: UInt64)?
    /// mach_host_self() returns a new send right each call; keep one.
    @ObservationIgnored private let host = mach_host_self()

    private init() {}

    func beginSampling() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { SystemStatsService.shared.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func endSampling() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    private func sample() {
        if let usage = readCPU() {
            cpuUsage = usage
            cpuHistory.append(usage)
            if cpuHistory.count > 30 { cpuHistory.removeFirst(cpuHistory.count - 30) }
        }
        if let used = readMemoryUsed() { memoryUsed = used }
        pressure = readPressure()
    }

    /// Overall CPU load since the previous sample (HOST_CPU_LOAD_INFO tick deltas).
    private func readCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { previousTicks = (used, total) }
        guard let previous = previousTicks, total > previous.total else { return nil }
        return Double(used - previous.used) / Double(total - previous.total)
    }

    /// Roughly Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func readMemoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * pageSize
    }

    /// The kernel's memory pressure level (what Activity Monitor's pressure graph colors reflect).
    private func readPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
