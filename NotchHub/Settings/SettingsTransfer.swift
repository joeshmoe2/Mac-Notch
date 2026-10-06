import AppKit
import UniformTypeIdentifiers

/// Export / import / reset of all `nh.*` preferences.
@MainActor
enum SettingsTransfer {
    private static var defaults: UserDefaults { .standard }

    static func currentSettings() -> [String: Any] {
        defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(Prefs.prefix) }
            .filter { $0.value is String || $0.value is NSNumber }
    }

    static func exportData() throws -> Data {
        var payload: [String: Any] = ["app": "NotchHub", "version": 1]
        payload["settings"] = currentSettings()
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    static func importData(_ data: Data) throws {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = payload["settings"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (key, value) in settings where key.hasPrefix(Prefs.prefix) {
            if value is String || value is NSNumber { defaults.set(value, forKey: key) }
        }
        applyChanges()
    }

    static func resetToDefaults() {
        for key in currentSettings().keys { defaults.removeObject(forKey: key) }
        applyChanges()
    }

    private static func applyChanges() {
        AppState.shared.registry.reload()
        NotchWindowManager.shared.rebuild()
        HotKeyService.shared.applyPreferences()
    }

    // MARK: Panels

    static func runExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "NotchHub Settings.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportData().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func runImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try importData(Data(contentsOf: url))
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
