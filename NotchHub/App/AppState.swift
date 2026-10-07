import SwiftUI

/// Process-wide state: the module registry and shared services.
@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    let registry: ModuleRegistry

    private init() {
        registry = ModuleRegistry(modules: AppState.makeModules())
    }

    /// The single place where modules are registered. Order here is the
    /// default tab order.
    private static func makeModules() -> [any NotchModule] {
        [
            TimerModule(),
            PomodoroModule(),
            NotesModule(),
            ShelfModule(),
            WeatherModule(),
            AudioModule(),
            CalendarModule(),
            RemindersModule(),
            ClipboardModule(),
            CameraModule(),
            QuickActionsModule(),
            WorldClocksModule(),
            CalculatorModule(),
            SystemStatsModule(),
        ]
    }

    func collapseNotch() {
        NotchWindowManager.shared.collapseAll()
    }

    func openNotchNotes() {
        module(NotesModule.self)?.openInCompanion(nil)
    }

    func prepareForExpand() {
        for module in registry.enabled { module.willExpand() }
    }

    /// Routes files dropped anywhere on the notch. Returns true if handled.
    @discardableResult
    func receiveDroppedFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, registry.isEnabled(ShelfModuleID), let shelf = module(ShelfModule.self) else { return false }
        shelf.add(urls)
        return true
    }

    func module<M: NotchModule>(_ type: M.Type) -> M? {
        registry.all.first { $0 is M } as? M
    }
}
