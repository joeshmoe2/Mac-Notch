import SwiftUI

struct PomodoroExpandedView: View {
    let module: PomodoroModule

    var body: some View {
        HStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: module.isRunning ? 1 : 3600)) { context in
                ZStack {
                    ProgressRing(progress: module.progress(at: context.date), color: module.phase.color, lineWidth: 8)
                        .animation(.linear(duration: 1), value: module.progress(at: context.date))
                    VStack(spacing: 2) {
                        Text(TimeFormat.clock(module.remaining(at: context.date)))
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        Text(module.phase.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(module.phase.color)
                    }
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(0..<module.sessionsBeforeLong, id: \.self) { i in
                        Circle()
                            .fill(i < module.sessionsInCycle ? PomodoroPhase.work.color : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                    Text("Cycle").font(.caption).foregroundStyle(.secondary)
                }
                Label("\(module.completedToday) focus session\(module.completedToday == 1 ? "" : "s") today",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
                FocusGuardStatus()

                HStack(spacing: 8) {
                    Button(action: module.toggle) {
                        Label(module.isRunning ? "Pause" : (module.hasStarted ? "Resume" : "Start"),
                              systemImage: module.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    Button(action: module.skip) { Label("Skip", systemImage: "forward.end.fill") }
                        .buttonStyle(PillButtonStyle())
                    Button(action: module.reset) { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

struct PomodoroCompactView: View {
    let module: PomodoroModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "leaf.fill", title: module.phase.title)
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: module.isRunning ? 1 : 3600)) { context in
                    HStack(spacing: 8) {
                        ProgressRing(progress: module.progress(at: context.date), color: module.phase.color, lineWidth: 3)
                            .frame(width: 22, height: 22)
                        Text(TimeFormat.clock(module.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    }
                }
            }
            HStack(spacing: 4) {
                IconButton(icon: module.isRunning ? "pause.fill" : "play.fill", size: 10, action: module.toggle)
                IconButton(icon: "forward.end.fill", size: 10, action: module.skip)
                Spacer()
                Text("\(module.completedToday) today").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct PomodoroSettingsView: View {
    let module: PomodoroModule
    @AppStorage(Prefs.pomodoroWork) private var work
    @AppStorage(Prefs.pomodoroShortBreak) private var shortBreak
    @AppStorage(Prefs.pomodoroLongBreak) private var longBreak
    @AppStorage(Prefs.pomodoroSessionsBeforeLong) private var sessions
    @AppStorage(Prefs.pomodoroAutoStart) private var autoStart
    @AppStorage(Prefs.pomodoroNotify) private var notify
    @AppStorage(Prefs.pomodoroSound) private var sound
    @AppStorage(Prefs.pomodoroSoundName) private var soundName

    var body: some View {
        Stepper("Focus: \(work) min", value: $work, in: 1...120)
        Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1...60)
        Stepper("Long break: \(longBreak) min", value: $longBreak, in: 1...90)
        Stepper("Sessions before long break: \(sessions)", value: $sessions, in: 1...12)
        Toggle("Auto-start next phase", isOn: $autoStart)
        Toggle("Notify at phase changes", isOn: $notify)
        Toggle("Play sound at phase changes", isOn: $sound)
        Picker("Sound", selection: $soundName) {
            ForEach(NotificationService.soundNames, id: \.self) { Text($0).tag($0) }
        }
        .disabled(!sound)
        FocusBlockingSettings()
        NotificationPermissionRow()
            .onChange(of: work) { module.applySettings() }
            .onChange(of: shortBreak) { module.applySettings() }
            .onChange(of: longBreak) { module.applySettings() }
    }
}

/// Small "Blocking 3 apps" line shown during a focus session.
private struct FocusGuardStatus: View {
    private var guardian: FocusGuard { .shared }
    @AppStorage(Prefs.focusBlockApps) private var blockApps
    @AppStorage(Prefs.focusUseFocusMode) private var useFocusMode

    var body: some View {
        if guardian.isActive, blockApps || useFocusMode {
            VStack(alignment: .leading, spacing: 2) {
                Label(statusText, systemImage: "shield.lefthalf.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PomodoroPhase.work.color)
                if let name = guardian.lastBlockedName {
                    Text("Blocked \(name)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        var parts: [String] = []
        if blockApps {
            let count = guardian.blockedApps.count
            parts.append("Blocking \(count) app\(count == 1 ? "" : "s")")
        }
        if useFocusMode { parts.append("Focus on") }
        return parts.joined(separator: " · ")
    }
}

/// Settings rows for app blocking and Focus (Do Not Disturb) during focus sessions.
struct FocusBlockingSettings: View {
    @AppStorage(Prefs.focusBlockApps) private var blockApps
    @AppStorage(Prefs.focusBlockedApps) private var blockedIDs
    @AppStorage(Prefs.focusBlockAction) private var blockAction
    @AppStorage(Prefs.focusUseFocusMode) private var useFocusMode
    @AppStorage(Prefs.focusOnShortcut) private var onShortcut
    @AppStorage(Prefs.focusOffShortcut) private var offShortcut
    private var guardian: FocusGuard { .shared }

    var body: some View {
        Toggle("Block distracting apps during focus", isOn: $blockApps)
            .onChange(of: blockApps) { guardian.blockingSettingChanged() }
        if blockApps {
            let apps = blockedIDs.idList.map(BlockableApp.init(bundleID:))
            if apps.isEmpty {
                Text("No apps blocked yet.").foregroundStyle(.secondary)
            }
            ForEach(apps) { app in
                HStack {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                    Spacer()
                    Button {
                        guardian.removeApp(app.bundleID)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Add Apps…") { guardian.runAddAppPanel() }
            Picker("When a blocked app opens", selection: $blockAction) {
                Text("Hide it").tag("hide")
                Text("Quit it").tag("quit")
            }
            Text("Blocking applies only while a focus phase is running (not during breaks or while paused).")
                .font(.caption).foregroundStyle(.secondary)
        }

        Toggle("Silence notifications with a Focus mode", isOn: $useFocusMode)
        if useFocusMode {
            TextField("Shortcut to turn Focus on", text: $onShortcut)
            TextField("Shortcut to turn Focus off", text: $offShortcut)
            Text("""
            macOS doesn't let apps switch Focus directly, so NotchHub runs two Shortcuts. In the Shortcuts app, create             "\(onShortcut)" with the action Set Focus → Do Not Disturb → On, and "\(offShortcut)" with Set Focus → Off.             To still see NotchHub's own "focus complete" alerts, allow NotchHub in that Focus's settings.
            """)
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open Shortcuts") { guardian.openShortcutsApp() }
                Button("Test On") { guardian.runShortcut(onShortcut) }
                Button("Test Off") { guardian.runShortcut(offShortcut) }
            }
            if let error = guardian.shortcutError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
