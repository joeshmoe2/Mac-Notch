import SwiftUI

/// A strongly typed UserDefaults key with its default value.
///
/// Every key is namespaced with `nh.` so settings can be exported, imported
/// and reset generically (see `SettingsTransfer`).
struct PrefKey<Value> {
    let name: String
    let defaultValue: Value

    init(_ name: String, _ defaultValue: Value) {
        self.name = "nh." + name
        self.defaultValue = defaultValue
    }

    /// Current value, read straight from UserDefaults (for non-view code).
    var value: Value {
        (UserDefaults.standard.object(forKey: name) as? Value) ?? defaultValue
    }

    func set(_ newValue: Value) {
        UserDefaults.standard.set(newValue, forKey: name)
    }
}

// MARK: - @AppStorage conveniences

extension AppStorage where Value == Bool {
    init(_ key: PrefKey<Bool>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

extension AppStorage where Value == Int {
    init(_ key: PrefKey<Int>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

extension AppStorage where Value == Double {
    init(_ key: PrefKey<Double>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

extension AppStorage where Value == String {
    init(_ key: PrefKey<String>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

// MARK: - All keys

enum Prefs {
    static let prefix = "nh."

    // General
    static let displayMode = PrefKey("general.displayMode", DisplayMode.builtIn.rawValue)
    static let virtualNotch = PrefKey("general.virtualNotch", true)
    static let hotKeyEnabled = PrefKey("general.hotKeyEnabled", true)
    /// Carbon virtual key code (default: kVK_ANSI_N).
    static let hotKeyCode = PrefKey("general.hotKeyCode", 45)
    /// Carbon modifier mask (default: cmdKey | optionKey).
    static let hotKeyModifiers = PrefKey("general.hotKeyModifiers", 256 | 2048)

    // Behavior
    static let hoverDelay = PrefKey("behavior.hoverDelay", 0.15)
    static let closeDelay = PrefKey("behavior.closeDelay", 0.4)
    static let expandOnDrag = PrefKey("behavior.expandOnDrag", true)
    static let haptics = PrefKey("behavior.haptics", true)
    static let openOnClick = PrefKey("behavior.openOnClick", false)
    static let rememberLastTab = PrefKey("behavior.rememberLastTab", true)
    static let lastTab = PrefKey("behavior.lastTab", "home")

    // Modules (comma separated module ids)
    static let moduleOrder = PrefKey("modules.order", "")
    static let disabledModules = PrefKey("modules.disabled", "")
    static let homeModules = PrefKey("modules.home", "timer,pomodoro,weather,audio,notes")
    static let liveActivityOrder = PrefKey("modules.liveOrder", "audio,pomodoro,timer")
    static let disabledLiveActivities = PrefKey("modules.liveDisabled", "")

    // Appearance
    static let expandedWidth = PrefKey("appearance.width", 640.0)
    static let expandedHeight = PrefKey("appearance.height", 250.0)
    static let cornerRadius = PrefKey("appearance.cornerRadius", 24.0)
    static let accentColor = PrefKey("appearance.accent", "#0A84FF")
    static let contentAppearance = PrefKey("appearance.content", ContentAppearance.dark.rawValue)
    static let background = PrefKey("appearance.background", BackgroundStyle.black.rawValue)
    static let animationSpeed = PrefKey("appearance.animationSpeed", 1.0)
    static let fontSize = PrefKey("appearance.fontSize", 13.0)
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case builtIn, main, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .builtIn: "Built-in display"
        case .main: "Main display"
        case .all: "All displays"
        }
    }
}

enum ContentAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case black, material
    var id: String { rawValue }
    var label: String { self == .black ? "Pure black" : "Blurred material" }
}

extension String {
    /// Splits a comma separated id list.
    var idList: [String] {
        split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension Array where Element == String {
    var joinedIDs: String { joined(separator: ",") }
}
