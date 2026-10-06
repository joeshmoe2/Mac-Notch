import SwiftUI

/// UI state for the notch on a single screen.
@Observable
@MainActor
final class NotchViewModel {
    enum State { case collapsed, expanded }

    var state: State = .collapsed
    var geometry: NotchGeometry
    /// "home" or a module id.
    var selectedTab: String
    /// True while a drag with files hovers over the notch's SwiftUI drop zone.
    var isDropTargeted = false
    /// True while the user drags files anywhere on screen after we expanded for them.
    var isDraggingFile = false
    /// Set while a popover/menu/share sheet is open so the notch doesn't collapse under it.
    var suppressAutoClose = false

    /// Expanded size from preferences (updated by the window controller).
    var expandedSize: CGSize

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.selectedTab = Prefs.rememberLastTab.value ? Prefs.lastTab.value : "home"
        self.expandedSize = CGSize(width: Prefs.expandedWidth.value, height: Prefs.expandedHeight.value)
    }

    var isExpanded: Bool { state == .expanded }

    /// Width of each "wing" beside the notch used by live activities.
    var wingWidth: CGFloat { max(44, geometry.notchSize.height * 1.4 + 10) }

    /// Live activity currently shown in the collapsed notch, if any.
    var liveActivity: LiveActivity? {
        AppState.shared.registry.currentLiveActivity
    }

    var collapsedSize: CGSize {
        var size = geometry.notchSize
        if liveActivity != nil { size.width += wingWidth * 2 }
        return size
    }

    var currentSize: CGSize {
        isExpanded ? CGSize(width: max(expandedSize.width, collapsedSize.width), height: expandedSize.height) : collapsedSize
    }

    func select(tab: String) {
        selectedTab = tab
        Prefs.lastTab.set(tab)
    }
}
