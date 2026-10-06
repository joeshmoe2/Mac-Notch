import SwiftUI

extension Prefs {
    static let timerSound = PrefKey("timer.sound", true)
    static let timerSoundName = PrefKey("timer.soundName", "Glass")
}

/// Multiple simultaneous countdown timers.
@Observable
@MainActor
final class TimerModule: NotchModule {
    let id = "timer"
    let name = "Timer"
    let icon = "timer"

    private(set) var timers: [CountdownTimer] = []
    @ObservationIgnored private var completionTasks: [UUID: Task<Void, Never>] = [:]

    static let presets: [Int] = [1, 5, 10, 15]

    // MARK: Actions

    func start(minutes: Int) {
        start(duration: TimeInterval(minutes * 60), label: "\(minutes) min")
    }

    func start(duration: TimeInterval, label: String) {
        NotificationService.shared.requestAuthorizationIfNeeded()
        var timer = CountdownTimer(label: label.isEmpty ? TimeFormat.clock(duration) : label, duration: duration)
        timer.endDate = .now.addingTimeInterval(duration)
        timers.append(timer)
        scheduleCompletion(for: timer)
    }

    func pause(_ id: UUID) {
        guard let i = index(id), timers[i].isRunning else { return }
        timers[i].pausedRemaining = timers[i].remaining()
        timers[i].endDate = nil
        cancelCompletion(id)
    }

    func resume(_ id: UUID) {
        guard let i = index(id), !timers[i].isRunning, !timers[i].isFinished else { return }
        timers[i].endDate = .now.addingTimeInterval(timers[i].pausedRemaining)
        scheduleCompletion(for: timers[i])
    }

    func reset(_ id: UUID) {
        guard let i = index(id) else { return }
        cancelCompletion(id)
        timers[i].endDate = nil
        timers[i].isFinished = false
        timers[i].pausedRemaining = timers[i].duration
    }

    func remove(_ id: UUID) {
        cancelCompletion(id)
        timers.removeAll { $0.id == id }
    }

    func clearFinished() {
        timers.removeAll { $0.isFinished }
    }

    // MARK: Completion

    private func index(_ id: UUID) -> Int? { timers.firstIndex { $0.id == id } }

    private func scheduleCompletion(for timer: CountdownTimer) {
        cancelCompletion(timer.id)
        let delay = timer.remaining()
        let id = timer.id
        completionTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.complete(id)
        }
    }

    private func cancelCompletion(_ id: UUID) {
        completionTasks[id]?.cancel()
        completionTasks[id] = nil
    }

    private func complete(_ id: UUID) {
        guard let i = index(id) else { return }
        timers[i].isFinished = true
        timers[i].endDate = nil
        timers[i].pausedRemaining = 0
        completionTasks[id] = nil
        NotificationService.shared.post(title: "Timer finished", body: timers[i].label)
        if Prefs.timerSound.value {
            NotificationService.shared.playSound(named: Prefs.timerSoundName.value)
        }
    }

    // MARK: NotchModule

    var supportsLiveActivity: Bool { true }

    var liveActivity: LiveActivity? {
        let running = timers.filter(\.isRunning)
        guard let next = running.min(by: { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }) else {
            if timers.contains(where: \.isFinished) {
                return LiveActivity(moduleID: id) {
                    Image(systemName: "bell.fill").foregroundStyle(.orange)
                } trailing: {
                    Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            return nil
        }
        let count = running.count
        return LiveActivity(moduleID: id) {
            HStack(spacing: 2) {
                Image(systemName: "timer").foregroundStyle(.orange)
                if count > 1 { Text("\(count)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13, weight: .semibold))
        } trailing: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimeFormat.clock(next.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    func compactView() -> AnyView { AnyView(TimerCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(TimerExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(TimerSettingsView()) }
}
