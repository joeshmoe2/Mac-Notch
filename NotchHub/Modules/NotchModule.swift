import SwiftUI

/// A self-contained feature that lives in the notch.
///
/// To add a module: create a class conforming to `NotchModule`, then register
/// it in `AppState.init` (see README "Adding a module").
@MainActor
protocol NotchModule: AnyObject {
    /// Stable identifier, used for persistence. Never change it once shipped.
    var id: String { get }
    var name: String { get }
    /// SF Symbol name used in the tab bar and settings.
    var icon: String { get }

    /// Small tile shown on the Home dashboard.
    func compactView() -> AnyView
    /// Full content shown when the module's tab is selected.
    func expandedView() -> AnyView
    /// Module-specific preferences, embedded in the Settings window.
    func settingsView() -> AnyView

    /// Whether this module can ever show a live activity (shown in Settings).
    var supportsLiveActivity: Bool { get }
    /// The live activity to show in the collapsed notch right now, or nil.
    /// Implementations should read only observable state so SwiftUI updates automatically.
    var liveActivity: LiveActivity? { get }

    /// Called when the module is enabled/disabled so it can start or stop work.
    func setActive(_ active: Bool)
    /// Called right before the notch expands (e.g. to refresh stale data).
    func willExpand()
}

extension NotchModule {
    var isEnabled: Bool { AppState.shared.registry.isEnabled(id) }
    var supportsLiveActivity: Bool { false }
    var liveActivity: LiveActivity? { nil }
    func setActive(_ active: Bool) {}
    func willExpand() {}
    func settingsView() -> AnyView {
        AnyView(Text("No settings for this module.").foregroundStyle(.secondary))
    }
}

/// Content shown on either side of the hardware notch while collapsed.
struct LiveActivity {
    let moduleID: String
    let leading: AnyView
    let trailing: AnyView

    init<L: View, T: View>(moduleID: String, @ViewBuilder leading: () -> L, @ViewBuilder trailing: () -> T) {
        self.moduleID = moduleID
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
    }
}
