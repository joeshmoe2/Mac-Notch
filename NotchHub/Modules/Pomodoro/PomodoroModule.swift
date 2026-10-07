import SwiftUI

extension Prefs {
    static let pomodoroWork = PrefKey("pomodoro.work", 25)
    static let pomodoroShortBreak = PrefKey("pomodoro.shortBreak", 5)
    static let pomodoroLongBreak = PrefKey("pomodoro.longBreak", 15)
    static let pomodoroSessionsBeforeLong = PrefKey("pomodoro.sessionsBeforeLong", 4)
    static let pomodoroAutoStart = PrefKey("pomodoro.autoStart", false)
    static let pomodoroSound = PrefKey("pomodoro.sound", true)
    static let pomodoroSoundName = PrefKey("pomodoro.soundName", "Hero")
    static let pomodoroNotify = PrefKey("pomodoro.notify", true)
    // Daily stats (not user-facing settings, but simplest to keep in defaults).
    static let pomodoroCompletedDay = PrefKey("pomodoro.stats.day", "")
    static let pomodoroCompletedCount = PrefKey("pomodoro.stats.count", 0)
}

enum PomodoroPhase: String, Codable {
    case work, shortBreak, longBreak

    var title: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var color: Color {
        switch self {
        case .work: Color(red: 1, green: 0.27, blue: 0.23)
        case .shortBreak: Color(red: 0.2, green: 0.84, blue: 0.29)
        case .longBreak: Color(red: 0.25, green: 0.78, blue: 0.85)
        }
    }

    var minutes: Int {
        switch self {
        case .work: Prefs.pomodoroWork.value
        case .shortBreak: Prefs.pomodoroShortBreak.value
        case .longBreak: Prefs.pomodoroLongBreak.value
        }
    }
}

/// Classic Pomodoro cycle: focus → short break, with a long break every N sessions.
@Observable
@MainActor
final class PomodoroModule: NotchModule {
    let id = "pomodoro"
    let name = "Pomodoro"
    let icon = "leaf.fill"

    private(set) var phase: PomodoroPhase = .work
    /// Set while running.
    private(set) var endDate: Date?
    /// Remaining while paused / idle.
    private(set) var pausedRemaining: TimeInterval
    /// Focus sessions completed in the current cycle (resets after a long break).
    private(set) var sessionsInCycle = 0
    private(set) var completedToday = 0
    /// True once the timer has been started in the current phase.
    private(set) var hasStarted = false

    /// Set when a phase ran out while NotchHub was quit; shown until the next action.
    private(set) var completedWhileClosed: PomodoroPhase?

    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    /// True while restoring saved state in `init` (no side effects then).
    @ObservationIgnored private var isRestoring = false

    private static let stateFile = "pomodoro-state.json"

    /// What's saved between launches. The end date (not a tick count) is stored,
    /// so time keeps passing while the app is closed.
    private struct SavedState: Codable {
        var phase: PomodoroPhase
        var endDate: Date?
        var pausedRemaining: TimeInterval
        var sessionsInCycle: Int
        var hasStarted: Bool
    }

    init() {
        pausedRemaining = TimeInterval(PomodoroPhase.work.minutes * 60)
        loadStats()
        restoreState()
    }

    private func restoreState() {
        guard let saved = JSONStore.load(SavedState.self, from: Self.stateFile) else { return }
        isRestoring = true
        defer { isRestoring = false }
        phase = saved.phase
        sessionsInCycle = saved.sessionsInCycle
        hasStarted = saved.hasStarted
        pausedRemaining = saved.pausedRemaining
        endDate = saved.endDate
        if let end = saved.endDate {
            if end > .now {
                schedulePhaseEnd()
            } else {
                // Finished while we were closed: count it and move on, but don't auto-start.
                completedWhileClosed = phase
                advance(countCompleted: true, allowAutoStart: false)
            }
        }
        persist()
    }

    private func persist() {
        JSONStore.save(SavedState(phase: phase, endDate: endDate, pausedRemaining: pausedRemaining,
                                  sessionsInCycle: sessionsInCycle, hasStarted: hasStarted),
                       to: Self.stateFile)
    }

    var isRunning: Bool { endDate != nil }
    var phaseDuration: TimeInterval { TimeInterval(phase.minutes * 60) }
    var sessionsBeforeLong: Int { max(1, Prefs.pomodoroSessionsBeforeLong.value) }

    func remaining(at now: Date = .now) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining
    }

    func progress(at now: Date = .now) -> Double {
        guard phaseDuration > 0 else { return 0 }
        return 1 - remaining(at: now) / phaseDuration
    }

    // MARK: Controls

    func start() {
        guard !isRunning else { return }
        completedWhileClosed = nil
        NotificationService.shared.requestAuthorizationIfNeeded()
        hasStarted = true
        endDate = .now.addingTimeInterval(pausedRemaining)
        schedulePhaseEnd()
        syncFocusGuard()
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining()
        endDate = nil
        phaseTask?.cancel()
        syncFocusGuard()
    }

    func toggle() { isRunning ? pause() : start() }

    /// Skips to the next phase without counting the current one.
    func skip() {
        advance(countCompleted: false)
    }

    /// Back to the start of a fresh focus session.
    func reset() {
        phaseTask?.cancel()
        completedWhileClosed = nil
        phase = .work
        sessionsInCycle = 0
        endDate = nil
        hasStarted = false
        pausedRemaining = phaseDuration
        syncFocusGuard()
    }

    /// Re-reads durations after settings change (only affects idle phases).
    func applySettings() {
        if !hasStarted { pausedRemaining = phaseDuration }
    }

    // MARK: Phase machine

    private func schedulePhaseEnd() {
        phaseTask?.cancel()
        let delay = remaining()
        phaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.phaseFinished()
        }
    }

    private func phaseFinished() {
        let finished = phase
        advance(countCompleted: true)
        let message: String
        switch finished {
        case .work: message = phase == .longBreak ? "Great work! Time for a long break." : "Time for a short break."
        case .shortBreak, .longBreak: message = "Break's over. Ready to focus?"
        }
        if Prefs.pomodoroNotify.value {
            NotificationService.shared.post(title: "\(finished.title) complete", body: message)
        }
        if Prefs.pomodoroSound.value {
            NotificationService.shared.playSound(named: Prefs.pomodoroSoundName.value)
        }
    }

    private func advance(countCompleted: Bool, allowAutoStart: Bool = true) {
        phaseTask?.cancel()
        let wasRunning = isRunning
        if phase == .work {
            if countCompleted { recordCompletedSession() }
            sessionsInCycle += 1
            phase = sessionsInCycle >= sessionsBeforeLong ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { sessionsInCycle = 0 }
            phase = .work
        }
        pausedRemaining = phaseDuration
        endDate = nil
        hasStarted = false
        // Auto-start after a natural completion if enabled; keep running after a skip.
        if (countCompleted && allowAutoStart && Prefs.pomodoroAutoStart.value) || (!countCompleted && wasRunning) {
            start()
        }
        syncFocusGuard()
    }

    /// Saves state and turns app blocking / Focus mode on only while a focus phase is running.
    private func syncFocusGuard() {
        persist()
        // During init the registry (and AppState) don't exist yet; setActive(_:) applies it later.
        guard !isRestoring else { return }
        FocusGuard.shared.setActive(isEnabled && phase == .work && isRunning, until: endDate)
    }

    // MARK: Stats

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    private func loadStats() {
        completedToday = Prefs.pomodoroCompletedDay.value == Self.todayKey ? Prefs.pomodoroCompletedCount.value : 0
    }

    private func recordCompletedSession() {
        loadStats()
        completedToday += 1
        Prefs.pomodoroCompletedDay.set(Self.todayKey)
        Prefs.pomodoroCompletedCount.set(completedToday)
    }

    // MARK: NotchModule

    func setActive(_ active: Bool) {
        // Also re-applies blocking for a focus session restored at launch.
        FocusGuard.shared.setActive(active && phase == .work && isRunning, until: endDate)
    }

    func willExpand() {
        loadStats()
        applySettings()
    }

    var supportsLiveActivity: Bool { true }

    var liveActivity: LiveActivity? {
        guard hasStarted else { return nil }
        let color = phase.color
        let running = isRunning
        return LiveActivity(moduleID: id) {
            TimelineView(.periodic(from: .now, by: running ? 1 : 3600)) { context in
                ProgressRing(progress: self.progress(at: context.date), color: color, lineWidth: 3)
                    .frame(width: 16, height: 16)
                    .opacity(running ? 1 : 0.5)
            }
        } trailing: {
            TimelineView(.periodic(from: .now, by: running ? 1 : 3600)) { context in
                Text(TimeFormat.clock(self.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    func compactView() -> AnyView { AnyView(PomodoroCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(PomodoroExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(PomodoroSettingsView(module: self)) }
}
