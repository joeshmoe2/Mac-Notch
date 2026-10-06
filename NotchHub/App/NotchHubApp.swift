import SwiftUI

@main
struct NotchHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// Status item icon. Also captures SwiftUI's `openSettings` action so the
/// notch panel (which lives outside the scene graph) can open Settings.
private struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "rectangle.topthird.inset.filled")
            .onAppear { SettingsOpener.action = openSettings }
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Button("Toggle Notch") { NotchWindowManager.shared.toggle() }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit NotchHub") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Opens the SwiftUI Settings scene from anywhere (including AppKit code).
@MainActor
enum SettingsOpener {
    static var action: OpenSettingsAction?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let action {
            action()
        } else {
            // Fallback for older behaviour; may be ignored on macOS 14+.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        // Agent apps open Settings behind other windows; bring it forward.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true || $0.title.contains("Settings") }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
