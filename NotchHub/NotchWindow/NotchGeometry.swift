import AppKit

/// Describes the notch (hardware or virtual) on one screen.
struct NotchGeometry: Equatable {
    /// Size of the notch cut-out (or virtual pill), in points.
    var notchSize: CGSize
    /// Whether this screen has a physical camera housing.
    var isHardware: Bool

    static let virtualSize = CGSize(width: 190, height: 30)

    /// Detects the hardware notch using `safeAreaInsets` and the auxiliary
    /// top areas (the menu bar regions left and right of the notch).
    static func detect(on screen: NSScreen) -> NotchGeometry? {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 0 {
                // A couple of points of overdraw hides anti-aliasing seams.
                return NotchGeometry(notchSize: CGSize(width: width + 4, height: height), isHardware: true)
            }
        }
        return nil
    }

    /// The geometry to use: hardware notch if present, otherwise a virtual
    /// pill when allowed. Returns nil if nothing should be shown.
    static func resolve(on screen: NSScreen, allowVirtual: Bool) -> NotchGeometry? {
        if let hw = detect(on: screen) { return hw }
        guard allowVirtual else { return nil }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = max(24, min(menuBarHeight > 0 ? menuBarHeight : 24, 32))
        return NotchGeometry(notchSize: CGSize(width: virtualSize.width, height: height), isHardware: false)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// Stable-ish identifier used to key per-screen windows.
    var notchScreenKey: String {
        if let id = displayID { return "display-\(id)" }
        return localizedName
    }
}
