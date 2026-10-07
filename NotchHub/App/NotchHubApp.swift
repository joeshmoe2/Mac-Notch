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
    }
}

/// Status item icon.
private struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "rectangle.topthird.inset.filled")
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Button("Toggle Notch") { NotchWindowManager.shared.toggle() }
        Button("Open NotchNotes") { AppState.shared.openNotchNotes() }
        Divider()
        Button("Settings…") { SettingsOpener.open() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit NotchHub") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
