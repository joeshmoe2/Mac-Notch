import ServiceManagement
import SwiftUI

/// The app's Settings window (SwiftUI `Settings` scene).
struct SettingsView: View {
    enum Page: Hashable {
        case general, behavior, modules, appearance, backup
        case module(String)
    }

    @Bindable private var router = SettingsRouter.shared
    private var registry: ModuleRegistry { AppState.shared.registry }

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                Section {
                    Label("General", systemImage: "gearshape").tag(Page.general)
                    Label("Behavior", systemImage: "cursorarrow.motionlines").tag(Page.behavior)
                    Label("Modules", systemImage: "square.grid.2x2").tag(Page.modules)
                    Label("Appearance", systemImage: "paintpalette").tag(Page.appearance)
                    Label("Backup & Reset", systemImage: "arrow.up.arrow.down.square").tag(Page.backup)
                }
                Section("Modules") {
                    ForEach(registry.ordered, id: \.id) { module in
                        Label(module.name, systemImage: module.icon).tag(Page.module(module.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail
                .formStyle(.grouped)
                .frame(minWidth: 460)
        }
        .frame(minWidth: 680, minHeight: 500)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general: GeneralSettingsView()
        case .behavior: BehaviorSettingsView()
        case .modules: ModulesSettingsView()
        case .appearance: AppearanceSettingsView()
        case .backup: BackupSettingsView()
        case .module(let id):
            if let module = registry.module(id: id) {
                Form {
                    Section {
                        Toggle("Enabled", isOn: Binding(
                            get: { registry.isEnabled(id) },
                            set: { registry.setEnabled(id, $0) }
                        ))
                    } header: {
                        Label(module.name, systemImage: module.icon).font(.headline)
                    }
                    Section("Options") { module.settingsView() }
                }
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage(Prefs.displayMode) private var displayMode
    @AppStorage(Prefs.virtualNotch) private var virtualNotch
    @AppStorage(Prefs.hotKeyEnabled) private var hotKeyEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Welcome") {
                LabeledContent("Introduction and permissions") {
                    Button("Show Onboarding Again") { OnboardingWindowController.shared.show() }
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Displays") {
                Picker("Show notch on", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Show a virtual notch on displays without one", isOn: $virtualNotch)
                Text("When the built-in display is closed or unavailable, the notch moves to the main display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard Shortcut") {
                Toggle("Toggle the notch with a global shortcut", isOn: $hotKeyEnabled)
                HotKeyRecorder().disabled(!hotKeyEnabled)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
        if SMAppService.mainApp.status == .requiresApproval {
            launchError = "Approve NotchHub in System Settings → General → Login Items."
        }
    }
}

/// Click, then press a key combination (with ⌘, ⌥ or ⌃) to set the shortcut.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyCode) private var keyCode
    @AppStorage(Prefs.hotKeyModifiers) private var modifiers
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Shortcut") {
            Button(recording ? "Press keys… (Esc to cancel)" : HotKeyFormatter.string(keyCode: keyCode, modifiers: modifiers)) {
                recording ? stop() : start()
            }
            .frame(minWidth: 160)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            keyCode = Int(event.keyCode)
            modifiers = HotKeyFormatter.carbonModifiers(from: flags)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

// MARK: - Behavior

struct BehaviorSettingsView: View {
    @AppStorage(Prefs.hoverDelay) private var hoverDelay
    @AppStorage(Prefs.closeDelay) private var closeDelay
    @AppStorage(Prefs.expandOnDrag) private var expandOnDrag
    @AppStorage(Prefs.haptics) private var haptics
    @AppStorage(Prefs.openOnClick) private var openOnClick
    @AppStorage(Prefs.rememberLastTab) private var rememberLastTab

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open on click instead of hover", isOn: $openOnClick)
                LabeledSlider(title: "Hover delay", value: $hoverDelay, range: 0...1, step: 0.05, format: "%.2fs")
                    .disabled(openOnClick)
                Toggle("Expand when dragging files over the notch", isOn: $expandOnDrag)
                Toggle("Haptic feedback when opening", isOn: $haptics)
            }
            Section("Closing") {
                LabeledSlider(title: "Close delay", value: $closeDelay, range: 0...2, step: 0.05, format: "%.2fs")
                Text("The notch stays open while you're typing, dragging files, or using a menu. Press Esc or click elsewhere to close it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tabs") {
                Toggle("Reopen on the last used tab", isOn: $rememberLastTab)
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: String = "%.0f"

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Modules

struct ModulesSettingsView: View {
    private var registry: ModuleRegistry { AppState.shared.registry }

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(registry.ordered, id: \.id) { module in
                        ModuleSettingsRow(registry: registry, id: module.id, name: module.name, icon: module.icon)
                    }
                    .onMove { registry.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: listHeight(rows: registry.all.count))
            } header: {
                Text("Tabs")
            } footer: {
                Text("Drag to reorder tabs. \"Home\" adds the module to the Home dashboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                List {
                    ForEach(registry.liveOrder, id: \.self) { id in
                        LiveActivitySettingsRow(registry: registry, id: id)
                    }
                    .onMove { registry.moveLiveActivity(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: listHeight(rows: registry.liveOrder.count))
            } header: {
                Text("Live Activities")
            } footer: {
                Text("Shown beside the notch while collapsed. When several are active, the highest one in this list wins.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func listHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * 30 + 10
    }
}

private struct ModuleSettingsRow: View {
    let registry: ModuleRegistry
    let id: String
    let name: String
    let icon: String

    private var enabled: Binding<Bool> {
        Binding(get: { registry.isEnabled(id) }, set: { registry.setEnabled(id, $0) })
    }

    private var onHome: Binding<Bool> {
        Binding(get: { registry.isOnHome(id) }, set: { registry.setOnHome(id, $0) })
    }

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Image(systemName: icon).frame(width: 20)
            Text(name)
            Spacer()
            Toggle("Home", isOn: onHome)
                .toggleStyle(.checkbox)
                .disabled(!registry.isEnabled(id))
            Toggle("Enabled", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct LiveActivitySettingsRow: View {
    let registry: ModuleRegistry
    let id: String

    private var allowed: Binding<Bool> {
        Binding(get: { registry.isLiveActivityAllowed(id) }, set: { registry.setLiveActivityAllowed(id, $0) })
    }

    var body: some View {
        if let module = registry.module(id: id) {
            HStack {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Image(systemName: module.icon).frame(width: 20)
                Text(module.name)
                Spacer()
                Toggle("Show", isOn: allowed)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage(Prefs.expandedWidth) private var width
    @AppStorage(Prefs.expandedHeight) private var height
    @AppStorage(Prefs.cornerRadius) private var cornerRadius
    @AppStorage(Prefs.accentColor) private var accentHex
    @AppStorage(Prefs.contentAppearance) private var contentAppearance
    @AppStorage(Prefs.background) private var background
    @AppStorage(Prefs.animationSpeed) private var animationSpeed
    @AppStorage(Prefs.fontSize) private var fontSize

    var body: some View {
        Form {
            Section("Size") {
                LabeledSlider(title: "Width", value: $width, range: 480...1000, step: 10, format: "%.0f pt")
                LabeledSlider(title: "Height", value: $height, range: 180...420, step: 10, format: "%.0f pt")
                LabeledSlider(title: "Corner radius", value: $cornerRadius, range: 8...40, step: 1, format: "%.0f pt")
            }
            Section("Style") {
                ColorPicker("Accent color", selection: Binding(
                    get: { Color(hex: accentHex) ?? .accentColor },
                    set: { accentHex = $0.hexString }
                ), supportsOpacity: false)
                Picker("Content appearance", selection: $contentAppearance) {
                    ForEach(ContentAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Background", selection: $background) {
                    ForEach(BackgroundStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("Pure black blends seamlessly with the hardware notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Motion & Text") {
                LabeledSlider(title: "Animation speed", value: $animationSpeed, range: 0.5...2, step: 0.1, format: "%.1f×")
                LabeledSlider(title: "Font size", value: $fontSize, range: 11...17, step: 1, format: "%.0f pt")
            }
        }
    }
}

// MARK: - Backup

struct BackupSettingsView: View {
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Export & Import") {
                Text("Settings are saved as JSON. Notes, timers and shelf items are not included.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export Settings…") { SettingsTransfer.runExportPanel() }
                    Button("Import Settings…") { SettingsTransfer.runImportPanel() }
                }
            }
            Section("Reset") {
                Button("Reset All Settings to Defaults", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset all NotchHub settings?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { SettingsTransfer.resetToDefaults() }
                    } message: {
                        Text("Your notes and shelf items are kept.")
                    }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Button("Quit NotchHub") { NSApp.terminate(nil) }
            }
        }
    }
}
