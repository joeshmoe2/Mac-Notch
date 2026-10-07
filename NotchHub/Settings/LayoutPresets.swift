import SwiftUI

extension Prefs {
    /// JSON-encoded [LayoutPreset].
    static let layoutPresets = PrefKey("presets.items", "[]")
    /// Id of the preset applied last ("" = none).
    static let activePreset = PrefKey("presets.active", "")
}

/// A named snapshot of the module layout and appearance.
struct LayoutPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// Setting name (e.g. "nh.modules.order") → value. Only strings and numbers.
    var values: [String: PresetValue]

    enum PresetValue: Codable, Equatable {
        case string(String), double(Double), bool(Bool)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) }
            else if let d = try? c.decode(Double.self) { self = .double(d) }
            else { self = .string(try c.decode(String.self)) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .double(let d): try c.encode(d)
            case .bool(let b): try c.encode(b)
            }
        }
    }
}

/// Saves and applies layout presets: module order, enabled modules, Home
/// dashboard, live-activity priority and appearance.
@Observable
@MainActor
final class LayoutPresetStore {
    static let shared = LayoutPresetStore()

    private(set) var presets: [LayoutPreset] = []
    private(set) var activeID: UUID?

    /// The settings a preset captures.
    private static let keys: [String] = [
        Prefs.moduleOrder.name, Prefs.disabledModules.name, Prefs.homeModules.name,
        Prefs.liveActivityOrder.name, Prefs.disabledLiveActivities.name,
        Prefs.expandedWidth.name, Prefs.expandedHeight.name, Prefs.cornerRadius.name,
        Prefs.accentColor.name, Prefs.contentAppearance.name, Prefs.background.name,
        Prefs.animationSpeed.name, Prefs.fontSize.name,
    ]

    private init() { reload() }

    func reload() {
        presets = (try? JSONDecoder().decode([LayoutPreset].self, from: Data(Prefs.layoutPresets.value.utf8))) ?? []
        activeID = UUID(uuidString: Prefs.activePreset.value)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            Prefs.layoutPresets.set(json)
        }
    }

    private static func snapshot() -> [String: LayoutPreset.PresetValue] {
        var values: [String: LayoutPreset.PresetValue] = [:]
        let defaults = UserDefaults.standard
        for key in keys {
            guard let value = defaults.object(forKey: key) else { continue }
            switch value {
            case let s as String: values[key] = .string(s)
            case let n as NSNumber:
                // NSNumber booleans report CFBoolean's type id.
                if CFGetTypeID(n) == CFBooleanGetTypeID() { values[key] = .bool(n.boolValue) } else { values[key] = .double(n.doubleValue) }
            default: break
            }
        }
        return values
    }

    /// Saves the current layout and appearance as a new preset.
    func saveCurrent(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let preset = LayoutPreset(name: trimmed, values: Self.snapshot())
        presets.append(preset)
        activeID = preset.id
        Prefs.activePreset.set(preset.id.uuidString)
        save()
    }

    /// Replaces a preset's contents with the current layout.
    func overwrite(_ preset: LayoutPreset) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[i].values = Self.snapshot()
        save()
    }

    func rename(_ preset: LayoutPreset, to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        presets[i].name = trimmed
        save()
    }

    func delete(_ preset: LayoutPreset) {
        presets.removeAll { $0.id == preset.id }
        if activeID == preset.id {
            activeID = nil
            Prefs.activePreset.set("")
        }
        save()
    }

    func apply(_ preset: LayoutPreset) {
        let defaults = UserDefaults.standard
        for key in Self.keys {
            switch preset.values[key] {
            case .string(let s)?: defaults.set(s, forKey: key)
            case .double(let d)?:
                // Integer-valued settings must stay integers so typed reads (as? Int) keep working.
                if d.rounded() == d, abs(d) < 1e9, key != Prefs.expandedWidth.name, key != Prefs.expandedHeight.name,
                   key != Prefs.cornerRadius.name, key != Prefs.animationSpeed.name, key != Prefs.fontSize.name {
                    defaults.set(Int(d), forKey: key)
                } else {
                    defaults.set(d, forKey: key)
                }
            case .bool(let b)?: defaults.set(b, forKey: key)
            case nil: defaults.removeObject(forKey: key)
            }
        }
        activeID = preset.id
        Prefs.activePreset.set(preset.id.uuidString)
        AppState.shared.registry.reload()
        NotchWindowManager.shared.relayout()
    }
}

/// Settings → Presets page.
struct LayoutPresetsSettingsView: View {
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    private var store: LayoutPresetStore { .shared }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Preset name", text: $newName, prompt: Text("e.g. Work, Focus, Minimal"))
                        .onSubmit(save)
                    Button("Save Current Layout", action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("New Preset")
            } footer: {
                Text("A preset remembers module order, which modules are on, the Home dashboard, live-activity priority and appearance (size, colors, font, animation). Switch presets here or from the menu bar icon.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Presets") {
                if store.presets.isEmpty {
                    Text("No presets yet.").foregroundStyle(.secondary)
                }
                ForEach(store.presets) { preset in
                    HStack {
                        if renaming == preset.id {
                            TextField("Name", text: $renameText)
                                .onSubmit {
                                    store.rename(preset, to: renameText)
                                    renaming = nil
                                }
                        } else {
                            Image(systemName: store.activeID == preset.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.activeID == preset.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                .accessibilityLabel(store.activeID == preset.id ? "Active" : "Inactive")
                            Text(preset.name)
                        }
                        Spacer()
                        Button("Apply") { store.apply(preset) }
                        Menu {
                            Button("Update with Current Layout") { store.overwrite(preset) }
                            Button("Rename") {
                                renameText = preset.name
                                renaming = preset.id
                            }
                            Divider()
                            Button("Delete", role: .destructive) { store.delete(preset) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("More actions for \(preset.name)")
                    }
                }
            }
        }
    }

    private func save() {
        store.saveCurrent(named: newName)
        newName = ""
    }
}

/// "Layout Preset" submenu for the menu bar icon.
struct LayoutPresetsMenu: View {
    private var store: LayoutPresetStore { .shared }

    var body: some View {
        Menu("Layout Preset") {
            if store.presets.isEmpty {
                Text("No presets saved")
            }
            ForEach(store.presets) { preset in
                Toggle(preset.name, isOn: Binding(
                    get: { store.activeID == preset.id },
                    set: { _ in store.apply(preset) }
                ))
            }
            Divider()
            Button("Manage Presets…") { SettingsOpener.open(page: .presets) }
        }
    }
}
