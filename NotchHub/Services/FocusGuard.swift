import AppKit
import UniformTypeIdentifiers

extension Prefs {
    static let focusBlockApps = PrefKey("pomodoro.blockApps", false)
    /// Comma separated bundle identifiers.
    static let focusBlockedApps = PrefKey("pomodoro.blockedApps", "")
    /// "shield" (full-screen block screen), "hide" or "quit".
    static let focusBlockAction = PrefKey("pomodoro.blockAction", "shield")
    static let focusUseFocusMode = PrefKey("pomodoro.useFocusMode", false)
    static let focusOnShortcut = PrefKey("pomodoro.focusOnShortcut", "NotchHub Focus On")
    static let focusOffShortcut = PrefKey("pomodoro.focusOffShortcut", "NotchHub Focus Off")
}

struct BlockableApp: Identifiable, Hashable {
    let bundleID: String
    var id: String { bundleID }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var name: String {
        guard let url else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var icon: NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Blocks distracting apps (and optionally turns on a macOS Focus) while a
/// Pomodoro focus session is running.
///
/// - Apps: when a blocked app is launched or brought to the front, it is
///   hidden (or quit, if chosen). Apps already running are handled when the
///   session starts. Event-driven via NSWorkspace notifications, no polling.
/// - Notifications: macOS has no public API to toggle Do Not Disturb / Focus,
///   so we run two user-created Shortcuts (`shortcuts run "<name>"`) that use
///   the "Set Focus" action.
@Observable
@MainActor
final class FocusGuard {
    static let shared = FocusGuard()

    private(set) var isActive = false
    /// Most recently blocked app name, shown in the Pomodoro UI.
    private(set) var lastBlockedName: String?
    private(set) var shortcutError: String?
    /// When the current focus phase ends (shown on the block screen).
    private(set) var sessionEnd: Date?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastNotified: [String: Date] = [:]

    private init() {}

    // MARK: Blocked app list

    var blockedApps: [BlockableApp] {
        Prefs.focusBlockedApps.value.idList.map(BlockableApp.init(bundleID:))
    }

    func addApps(at urls: [URL]) {
        var ids = Prefs.focusBlockedApps.value.idList
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, !ids.contains(id) else { continue }
            ids.append(id)
        }
        Prefs.focusBlockedApps.set(ids.joinedIDs)
        if isActive { enforceOnRunningApps() }
    }

    func removeApp(_ bundleID: String) {
        Prefs.focusBlockedApps.set(Prefs.focusBlockedApps.value.idList.filter { $0 != bundleID }.joinedIDs)
    }

    func runAddAppPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Block"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        addApps(at: panel.urls)
    }

    // MARK: Session

    /// Called by the Pomodoro module whenever its state changes.
    func setActive(_ active: Bool, until end: Date? = nil) {
        sessionEnd = active ? end : nil
        guard active != isActive else { return }
        isActive = active
        if active {
            if Prefs.focusBlockApps.value {
                startObserving()
                enforceOnRunningApps()
            }
            if Prefs.focusBlockWebsites.value { WebsiteBlocker.shared.apply(blocking: true) }
            if Prefs.focusUseFocusMode.value { runShortcut(Prefs.focusOnShortcut.value) }
        } else {
            stopObserving()
            lastBlockedName = nil
            FocusShield.shared.dismiss()
            if Prefs.focusBlockWebsites.value || WebsiteBlocker.shared.isBlocking {
                WebsiteBlocker.shared.apply(blocking: false)
            }
            if Prefs.focusUseFocusMode.value { runShortcut(Prefs.focusOffShortcut.value) }
        }
    }

    /// Applies a settings change made while a session is running.
    func blockingSettingChanged() {
        guard isActive else { return }
        if Prefs.focusBlockApps.value {
            startObserving()
            enforceOnRunningApps()
        } else {
            stopObserving()
            FocusShield.shared.dismiss()
        }
        WebsiteBlocker.shared.apply(blocking: Prefs.focusBlockWebsites.value)
    }

    /// Synchronous version for app termination so the Focus doesn't stay on.
    func deactivateForTermination() {
        guard isActive else { return }
        isActive = false
        stopObserving()
        if WebsiteBlocker.shared.isBlocking { WebsiteBlocker.shared.apply(blocking: false, wait: true) }
        if Prefs.focusUseFocusMode.value {
            runShortcut(Prefs.focusOffShortcut.value, wait: true)
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if let app { FocusGuard.shared.enforce(on: app) }
                }
            })
        }
    }

    private func stopObserving() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func enforceOnRunningApps() {
        let ids = Set(Prefs.focusBlockedApps.value.idList)
        for app in NSWorkspace.shared.runningApplications where ids.contains(app.bundleIdentifier ?? "") {
            enforce(on: app, notify: false)
        }
    }

    private func enforce(on app: NSRunningApplication, notify: Bool = true) {
        guard isActive, Prefs.focusBlockApps.value,
              let id = app.bundleIdentifier,
              Prefs.focusBlockedApps.value.idList.contains(id) else { return }
        let name = app.localizedName ?? id
        lastBlockedName = name
        switch Prefs.focusBlockAction.value {
        case "quit":
            app.terminate()
        case "hide":
            app.hide()
        default:
            // Block screen: hide the app and cover the screen with a reminder.
            app.hide()
            FocusShield.shared.show(appName: name, icon: app.icon)
            return
        }
        // Tell the user why, at most once a minute per app.
        if notify, Date.now.timeIntervalSince(lastNotified[id] ?? .distantPast) > 60 {
            lastNotified[id] = .now
            NotificationService.shared.post(title: "\(name) is blocked", body: "Stay focused! It's available again on your next break.")
        }
    }

    // MARK: Shortcuts (Focus / Do Not Disturb)

    func runShortcut(_ name: String, wait: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    FocusGuard.shared.shortcutError = ok ? nil
                        : "Couldn't run the shortcut \"\(trimmed)\". Check that it exists in the Shortcuts app."
                }
            }
        }
        do {
            try process.run()
            if wait { process.waitUntilExit() }
        } catch {
            shortcutError = "Couldn't run Shortcuts: \(error.localizedDescription)"
        }
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
