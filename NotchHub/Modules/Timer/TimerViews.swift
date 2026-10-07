import SwiftUI

struct TimerExpandedView: View {
    let module: TimerModule
    @State private var customText = ""
    @State private var labelText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick start").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(TimerModule.presets, id: \.self) { minutes in
                        Button("\(minutes)m") { module.start(minutes: minutes) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("mm or h:mm:ss", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onSubmit(startCustom)
                    TextField("Label", text: $labelText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(startCustom)
                    Button(action: startCustom) { Image(systemName: "play.fill") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .tooltip("Start custom timer")
                        .disabled(TimeFormat.parse(customText) == nil)
                }
            }
            .frame(width: 250)

            Divider().overlay(Color.white.opacity(0.1))

            if module.timers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No timers").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(module.timers) { timer in
                            TimerRow(module: module, timer: timer)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func startCustom() {
        guard let duration = TimeFormat.parse(customText) else { return }
        module.start(duration: duration, label: labelText)
        customText = ""
        labelText = ""
    }
}

private struct TimerRow: View {
    let module: TimerModule
    let timer: CountdownTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 3600)) { context in
            HStack(spacing: 10) {
                ProgressRing(progress: timer.progress(at: context.date), color: timer.isFinished ? .green : .orange, lineWidth: 3)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.isFinished ? "Done" : TimeFormat.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    Text(timer.finishedWhileClosed == true ? "\(timer.label) · finished while NotchHub was closed" : timer.label)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !timer.isFinished {
                    IconButton(icon: timer.isRunning ? "pause.fill" : "play.fill",
                               help: timer.isRunning ? "Pause timer" : "Resume timer") {
                        timer.isRunning ? module.pause(timer.id) : module.resume(timer.id)
                    }
                }
                IconButton(icon: "arrow.counterclockwise", help: "Reset timer") { module.reset(timer.id) }
                IconButton(icon: "xmark", help: "Remove timer") { module.remove(timer.id) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}

struct TimerCompactView: View {
    let module: TimerModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "timer", title: "Timers")
            if let timer = module.timers.first(where: { !$0.isFinished }) ?? module.timers.first {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timer.isFinished ? "Done" : TimeFormat.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                }
                Text(timer.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if module.timers.count > 1 {
                    Text("+\(module.timers.count - 1) more").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach([5, 15], id: \.self) { m in
                        Button("\(m)m") { module.start(minutes: m) }.buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
    }
}

struct TimerSettingsView: View {
    @AppStorage(Prefs.timerSound) private var playSound
    @AppStorage(Prefs.timerSoundName) private var soundName

    var body: some View {
        Toggle("Play sound when a timer finishes", isOn: $playSound)
        Picker("Sound", selection: $soundName) {
            ForEach(NotificationService.soundNames, id: \.self) { Text($0).tag($0) }
        }
        .disabled(!playSound)
        Button("Preview sound") { NotificationService.shared.playSound(named: soundName) }
        NotificationPermissionRow()
    }
}
