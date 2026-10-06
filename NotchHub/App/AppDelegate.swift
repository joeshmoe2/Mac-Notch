import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var defaultsObserver: NSObjectProtocol?
    private var defaultsDebounce: Task<Void, Never>?
    private var lastDisplaySignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppState.shared
        NotchWindowManager.shared.start()
        HotKeyService.shared.applyPreferences()
        // Remove any website block left behind by a crash.
        WebsiteBlocker.shared.cleanUpOnLaunch()
        lastDisplaySignature = displaySignature

        // React to settings changes (from the Settings window, import or reset).
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.module(NotesModule.self)?.saveNow()
        FocusGuard.shared.deactivateForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsOpener.open()
        return false
    }

    private var displaySignature: String {
        "\(Prefs.displayMode.value)|\(Prefs.virtualNotch.value)"
    }

    private func preferencesChanged() {
        defaultsDebounce?.cancel()
        defaultsDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            let signature = self.displaySignature
            if signature != self.lastDisplaySignature {
                self.lastDisplaySignature = signature
                NotchWindowManager.shared.rebuild()
            } else {
                NotchWindowManager.shared.relayout()
            }
            HotKeyService.shared.applyPreferences()
        }
    }
}
