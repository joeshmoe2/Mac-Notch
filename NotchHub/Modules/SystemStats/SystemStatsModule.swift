import SwiftUI

/// CPU usage, memory used and memory pressure. Samples only while visible.
@Observable
@MainActor
final class SystemStatsModule: NotchModule {
    let id = "systemStats"
    let name = "System"
    let icon = "cpu"

    var stats: SystemStatsService { .shared }

    func compactView() -> AnyView { AnyView(SystemStatsCompactView(stats: stats)) }
    func expandedView() -> AnyView { AnyView(SystemStatsExpandedView(stats: stats)) }
}

private extension SystemStatsService.Pressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

struct SystemStatsExpandedView: View {
    let stats: SystemStatsService

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ModuleTileHeader(icon: "cpu", title: "CPU")
                Text("\(Int((stats.cpuUsage * 100).rounded()))%")
                    .font(.system(size: 30, weight: .light).monospacedDigit())
                CPUHistoryChart(values: stats.cpuHistory)
                    .frame(height: 50)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CPU usage \(Int((stats.cpuUsage * 100).rounded())) percent")

            VStack(alignment: .leading, spacing: 6) {
                ModuleTileHeader(icon: "memorychip", title: "Memory")
                Text(formatBytes(stats.memoryUsed))
                    .font(.system(size: 30, weight: .light).monospacedDigit())
                ProgressView(value: Double(stats.memoryUsed), total: Double(max(stats.memoryTotal, 1)))
                    .tint(stats.pressure.color)
                Text("of \(formatBytes(stats.memoryTotal)) used")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Circle().fill(stats.pressure.color).frame(width: 8, height: 8)
                    Text("Memory pressure: \(stats.pressure.rawValue)").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        // Sampling is tied to this view being on screen.
        .onAppear { stats.beginSampling() }
        .onDisappear { stats.endSampling() }
    }
}

private struct CPUHistoryChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 2)
            let step = geo.size.width / CGFloat(29)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05))
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width - CGFloat(values.count - 1 - i) * step
                        let y = geo.size.height * (1 - CGFloat(min(max(v, 0), 1)))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .opacity(count > 1 ? 1 : 0)
            }
        }
    }
}

struct SystemStatsCompactView: View {
    let stats: SystemStatsService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "cpu", title: "System")
            HStack(spacing: 6) {
                Text("CPU").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((stats.cpuUsage * 100).rounded()))%").monospacedDigit()
            }
            HStack(spacing: 6) {
                Text("Memory").foregroundStyle(.secondary)
                Spacer()
                Circle().fill(stats.pressure.color).frame(width: 6, height: 6)
                Text(formatBytes(stats.memoryUsed)).monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .onAppear { stats.beginSampling() }
        .onDisappear { stats.endSampling() }
    }
}
