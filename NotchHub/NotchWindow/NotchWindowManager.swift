import AppKit

/// Creates one `NotchWindowController` per eligible screen and rebuilds them
/// when displays are connected/disconnected, the lid is closed, or the
/// resolution changes.
@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private(set) var controllers: [String: NotchWindowController] = [:]
    private var observers: [NSObjectProtocol] = []
    private var lastLayoutSignature = ""
    private var pendingRebuild: Task<Void, Never>?

    func start() {
        rebuild()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
        // Space / wake changes can reshuffle screens too.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
    }

    /// Debounced rebuild: display reconfiguration often fires several notifications.
    func scheduleRebuild() {
        pendingRebuild?.cancel()
        pendingRebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.rebuild()
        }
    }

    /// Screens that should get a notch window, with their geometry.
    private func targets() -> [(NSScreen, NotchGeometry)] {
        let allowVirtual = Prefs.virtualNotch.value
        let screens: [NSScreen]
        switch DisplayMode(rawValue: Prefs.displayMode.value) ?? .builtIn {
        case .all:
            screens = NSScreen.screens
        case .main:
            screens = NSScreen.main.map { [$0] } ?? []
        case .builtIn:
            // Prefer the built-in panel; fall back to the main screen when the lid is closed.
            if let builtIn = NSScreen.screens.first(where: { $0.isBuiltIn }) {
                screens = [builtIn]
            } else {
                screens = NSScreen.screens.first.map { [$0] } ?? []
            }
        }
        return screens.compactMap { screen in
            NotchGeometry.resolve(on: screen, allowVirtual: allowVirtual).map { (screen, $0) }
        }
    }

    /// Rebuilds windows only if the set of screens/geometry actually changed,
    /// otherwise just re-lays out existing panels.
    func rebuild() {
        let targets = targets()
        let signature = targets.map { "\($0.0.notchScreenKey)|\($0.0.frame)|\($0.1.notchSize)" }.joined(separator: ";")
        guard signature != lastLayoutSignature else {
            controllers.values.forEach { $0.layout() }
            return
        }
        lastLayoutSignature = signature
        controllers.values.forEach { $0.tearDown() }
        controllers.removeAll()
        for (screen, geometry) in targets {
            controllers[screen.notchScreenKey] = NotchWindowController(screen: screen, geometry: geometry)
        }
    }

    /// Re-applies size preferences without recreating windows.
    func relayout() {
        controllers.values.forEach { $0.layout() }
    }

    /// Toggles the notch on the screen containing the mouse (or the first one).
    func toggle() {
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { NSMouseInRect(mouse, $0.screen.frame, false) }
            ?? controllers.values.first
        target?.toggle()
    }

    func collapseAll() {
        controllers.values.forEach { $0.collapse() }
    }
}
