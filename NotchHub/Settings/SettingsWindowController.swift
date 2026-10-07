import AppKit
import SwiftUI

/// Which Settings page is showing. Shared so other code can open a specific page.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    var page: SettingsView.Page = .general
    private init() {}
}

/// Owns the Settings window.
///
/// The SwiftUI `Settings` scene can't be opened reliably from an agent app's
/// non-activating panel on macOS 14/15 (`showSettingsWindow:` is ignored and a
/// captured `openSettings` action only works once the menu bar label has
/// rendered). A plain NSWindow we control always works. While it's open the app
/// temporarily becomes a regular app so the window can come to the front and
/// appear in ⌘-Tab; it goes back to being an agent app when the window closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(page: SettingsView.Page? = nil) {
        if let page { SettingsRouter.shared.page = page }
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // Activation can lag a frame behind the policy change; make sure we end up in front.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchHub Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("NotchHubSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app (no Dock icon) unless another window still needs it.
        DispatchQueue.main.async {
            let otherWindows = NSApp.windows.contains {
                $0.isVisible && $0 !== self.window && $0.styleMask.contains(.titled)
            }
            if !otherWindows { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

/// Opens Settings from anywhere (notch, menu bar, AppKit code).
@MainActor
enum SettingsOpener {
    static func open(page: SettingsView.Page? = nil) {
        NotchWindowManager.shared.collapseAll()
        SettingsWindowController.shared.show(page: page)
    }
}
