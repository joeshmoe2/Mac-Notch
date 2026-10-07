import SwiftUI

extension Prefs {
    /// JSON-encoded [QuickAction].
    static let quickActionsItems = PrefKey("quickActions.items", "[]")
}

struct QuickAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    /// SF Symbol name.
    var symbol: String
    /// Name of the Apple Shortcut to run.
    var shortcut: String
}

/// A grid of buttons that each run an Apple Shortcut.
@Observable
@MainActor
final class QuickActionsModule: NotchModule {
    let id = "quickActions"
    let name = "Quick Actions"
    let icon = "square.grid.3x2.fill"

    enum RunState: Equatable { case running, succeeded, failed(String) }

    private(set) var actions: [QuickAction] = []
    private(set) var states: [UUID: RunState] = [:]
    /// The user's shortcut names (loaded on demand for the settings picker).
    private(set) var availableShortcuts: [String] = []

    init() {
        load()
    }

    // MARK: Storage (typed settings key, so it's included in settings export/import)

    func load() {
        let data = Data(Prefs.quickActionsItems.value.utf8)
        actions = (try? JSONDecoder().decode([QuickAction].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(actions), let json = String(data: data, encoding: .utf8) else { return }
        Prefs.quickActionsItems.set(json)
    }

    func add() {
        actions.append(QuickAction(title: "New Action", symbol: "bolt.fill", shortcut: availableShortcuts.first ?? ""))
        save()
    }

    func update(_ action: QuickAction) {
        guard let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[i] = action
        save()
    }

    func remove(_ id: UUID) {
        actions.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        actions.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func refreshShortcutList() async {
        availableShortcuts = await ShortcutsService.list()
    }

    // MARK: Running

    func run(_ action: QuickAction) {
        guard states[action.id] != .running else { return }
        states[action.id] = .running
        Task {
            let result = await ShortcutsService.run(action.shortcut)
            switch result {
            case .success: states[action.id] = .succeeded
            case .failure(let error): states[action.id] = .failed(error.message)
            }
            // Clear the ✓ / ✕ badge after a moment.
            try? await Task.sleep(for: .seconds(result.isSuccess ? 2 : 6))
            if states[action.id] != .running { states[action.id] = nil }
        }
    }

    func willExpand() {
        // Pick up changes made by settings import/reset.
        load()
    }

    // MARK: NotchModule

    func compactView() -> AnyView { AnyView(QuickActionsCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(QuickActionsExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(QuickActionsSettingsView(module: self)) }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}
