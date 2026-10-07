import AppKit
import SwiftUI
import UserNotifications

extension Prefs {
    static let onboardingCompleted = PrefKey("general.onboardingCompleted", false)
}

/// Shows the first-run welcome window. Like Settings, the app briefly becomes a
/// regular app while it's open so the window can come to the front.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func showIfNeeded() {
        guard !Prefs.onboardingCompleted.value else { return }
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView { [weak self] in self?.finish() })
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to NotchHub"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 520, height: 440))
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func finish() {
        Prefs.onboardingCompleted.set(true)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts as "seen"; it can be reopened from Settings → General.
        Prefs.onboardingCompleted.set(true)
        window = nil
        DispatchQueue.main.async {
            let others = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !others { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome, location, notifications, automation, done
}

/// Welcome → explain the notch → ask for each permission one at a time (each skippable).
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step: OnboardingStep = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Prefs.accentColor) private var accentHex
    @AppStorage(Prefs.hotKeyCode) private var hotKeyCode
    @AppStorage(Prefs.hotKeyModifiers) private var hotKeyModifiers

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .location: LocationStep()
                case .notifications: NotificationStep()
                case .automation: AutomationStep()
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                              removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Divider()
            footer
        }
        .frame(width: 520, height: 440)
        .tint(Color(hex: accentHex) ?? .accentColor)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s == step ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step != .welcome && step != .done {
                Button("Skip") { advance() }
                    .help("Skip this permission. You can grant it later in Settings.")
            }
            Button(step == .done ? "Start Using NotchHub" : "Continue") {
                step == .done ? onFinish() : advance()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Welcome to NotchHub").font(.largeTitle.bold())
            Text("Your MacBook's notch is now a hub for timers, music, weather, notes, files and more.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                OnboardingTip(icon: "cursorarrow.motionlines", text: "**Hover** over the notch to open it. Move away to close it.")
                OnboardingTip(icon: "tray.and.arrow.down", text: "**Drag files** onto the notch to keep them on the shelf.")
                OnboardingTip(icon: "keyboard", text: "Press **\(HotKeyFormatter.string(keyCode: hotKeyCode, modifiers: hotKeyModifiers))** to open or close it from anywhere.")
                OnboardingTip(icon: "menubar.rectangle", text: "Find **Settings** in the menu bar icon or the gear in the notch.")
            }
            .padding(.top, 6)
            Text("Next, NotchHub will ask for a few permissions. Each one is optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("You're all set").font(.largeTitle.bold())
            Text("Move your pointer to the notch to try it. You can change anything — including permissions — in Settings, and see this again from Settings → General.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingTip: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
        }
    }
}

private struct PermissionPage<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text(title).font(.title.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            content
                .padding(.top, 8)
        }
    }
}

private struct StatusLabel: View {
    let granted: Bool?
    var body: some View {
        switch granted {
        case .some(true): Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false): Label("Not allowed — you can change this in System Settings", systemImage: "xmark.circle").foregroundStyle(.orange)
        case .none: EmptyView()
        }
    }
}

private struct LocationStep: View {
    private var location: LocationService { .shared }

    private var granted: Bool? {
        switch location.authorization {
        case .notDetermined: nil
        case .denied, .restricted: false
        default: true
        }
    }

    var body: some View {
        PermissionPage(icon: "location.fill", title: "Local Weather",
                       message: "The Weather module uses your approximate location. If you'd rather not share it, you can type a city in Settings → Weather instead.") {
            if granted == nil {
                Button("Allow Location Access") { location.requestAuthorization() }
                    .buttonStyle(.bordered)
            }
            StatusLabel(granted: granted)
        }
    }
}

private struct NotificationStep: View {
    private var notifications: NotificationService { .shared }

    private var granted: Bool? {
        switch notifications.authorization {
        case .notDetermined: nil
        case .denied: false
        default: true
        }
    }

    var body: some View {
        PermissionPage(icon: "bell.badge.fill", title: "Notifications",
                       message: "Timers and Pomodoro tell you when time is up, even if the notch is closed.") {
            if granted == nil {
                Button("Allow Notifications") { notifications.requestAuthorizationIfNeeded() }
                    .buttonStyle(.bordered)
            }
            StatusLabel(granted: granted)
        }
        .onAppear { notifications.refreshStatus() }
    }
}

private struct AutomationStep: View {
    @State private var results: [MediaPlayer: AppleScriptRunner.Permission] = [:]
    @State private var working: MediaPlayer?

    private var players: [MediaPlayer] {
        [.music, .spotify].filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    var body: some View {
        PermissionPage(icon: "music.note", title: "Music & Spotify",
                       message: "To show what's playing and control playback, macOS asks once per app whether NotchHub may control it. The app may open briefly in the background.") {
            VStack(spacing: 10) {
                ForEach(players, id: \.self) { player in
                    HStack {
                        Text(player.displayName).frame(width: 80, alignment: .leading)
                        Spacer()
                        if working == player {
                            ProgressView().controlSize(.small)
                        } else if let result = results[player] {
                            StatusLabel(granted: result == .granted ? true : (result == .denied ? false : nil))
                            if result != .granted && result != .denied {
                                Button("Try Again") { request(player) }
                            }
                        } else {
                            Button("Allow \(player.displayName)") { request(player) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(width: 320)
                }
                if players.isEmpty {
                    Text("Neither Music nor Spotify is installed — nothing to do here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The Automation prompt only appears if the target app is running, so launch it hidden first.
    private func request(_ player: MediaPlayer) {
        working = player
        Task {
            if !player.isRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                try? await Task.sleep(for: .seconds(1.5))
            }
            let result = await AppleScriptRunner.permission(for: player.bundleID, ask: true)
            results[player] = result
            working = nil
            MediaService.shared.recheckPermissions()
        }
    }
}
