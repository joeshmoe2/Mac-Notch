import SwiftUI

/// Holds all known modules and the user's enable/order/home/live-activity choices.
@Observable
@MainActor
final class ModuleRegistry {
    /// All modules in their built-in default order.
    let all: [any NotchModule]

    private(set) var order: [String] = []
    private(set) var disabled: Set<String> = []
    private(set) var home: [String] = []
    private(set) var liveOrder: [String] = []
    private(set) var liveDisabled: Set<String> = []

    init(modules: [any NotchModule]) {
        self.all = modules
        reload()
    }

    /// Re-reads choices from UserDefaults (after import / reset).
    func reload() {
        let ids = all.map(\.id)
        var stored = Prefs.moduleOrder.value.idList.filter(ids.contains)
        stored += ids.filter { !stored.contains($0) }
        order = stored
        disabled = Set(Prefs.disabledModules.value.idList)
        home = Prefs.homeModules.value.idList.filter(ids.contains)
        var live = Prefs.liveActivityOrder.value.idList.filter(ids.contains)
        live += all.filter { $0.supportsLiveActivity && !live.contains($0.id) }.map(\.id)
        liveOrder = live
        liveDisabled = Set(Prefs.disabledLiveActivities.value.idList)
        for module in all { module.setActive(!disabled.contains(module.id)) }
    }

    func module(id: String) -> (any NotchModule)? {
        all.first { $0.id == id }
    }

    /// All modules in the user's order.
    var ordered: [any NotchModule] { order.compactMap(module(id:)) }

    /// Enabled modules in the user's order (these become tabs).
    var enabled: [any NotchModule] { ordered.filter { !disabled.contains($0.id) } }

    var homeModules: [any NotchModule] {
        home.compactMap(module(id:)).filter { !disabled.contains($0.id) }
    }

    func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }
    func isOnHome(_ id: String) -> Bool { home.contains(id) }
    func isLiveActivityAllowed(_ id: String) -> Bool { !liveDisabled.contains(id) }

    // MARK: Mutations (persisted)

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        Prefs.disabledModules.set(Array(disabled).sorted().joinedIDs)
        module(id: id)?.setActive(enabled)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        Prefs.moduleOrder.set(order.joinedIDs)
    }

    func setOnHome(_ id: String, _ on: Bool) {
        if on, !home.contains(id) {
            // Keep home in tab order.
            home = order.filter { home.contains($0) || $0 == id }
        } else if !on {
            home.removeAll { $0 == id }
        }
        Prefs.homeModules.set(home.joinedIDs)
    }

    func setLiveActivityAllowed(_ id: String, _ allowed: Bool) {
        if allowed { liveDisabled.remove(id) } else { liveDisabled.insert(id) }
        Prefs.disabledLiveActivities.set(Array(liveDisabled).sorted().joinedIDs)
    }

    func moveLiveActivity(fromOffsets source: IndexSet, toOffset destination: Int) {
        liveOrder.move(fromOffsets: source, toOffset: destination)
        Prefs.liveActivityOrder.set(liveOrder.joinedIDs)
    }

    /// Highest-priority live activity that is enabled and currently active.
    var currentLiveActivity: LiveActivity? {
        for id in liveOrder where !disabled.contains(id) && !liveDisabled.contains(id) {
            if let activity = module(id: id)?.liveActivity { return activity }
        }
        return nil
    }
}
