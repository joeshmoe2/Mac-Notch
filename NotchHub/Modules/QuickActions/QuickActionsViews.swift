import SwiftUI

struct QuickActionsExpandedView: View {
    let module: QuickActionsModule

    var body: some View {
        if module.actions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.3x2").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Add buttons that run your Shortcuts.").foregroundStyle(.secondary)
                Button("Set Up Quick Actions") { SettingsOpener.open(page: .module(module.id)) }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 8)], spacing: 8) {
                    ForEach(module.actions) { action in
                        QuickActionTile(module: module, action: action)
                    }
                }
            }
        }
    }
}

private struct QuickActionTile: View {
    let module: QuickActionsModule
    let action: QuickAction
    @State private var hovering = false

    private var state: QuickActionsModule.RunState? { module.states[action.id] }

    var body: some View {
        Button { module.run(action) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: action.symbol.isEmpty ? "bolt.fill" : action.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.tint)
                        .opacity(state == .running ? 0.25 : 1)
                    if state == .running {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 26)
                Text(action.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
            .overlay(alignment: .topTrailing) {
                switch state {
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(5)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red).padding(5)
                default:
                    EmptyView()
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .tooltip(tooltip, edge: .top) { hovering = $0 }
    }

    private var tooltip: String {
        if case .failed(let message) = state { return message }
        return "Run “\(action.shortcut)”"
    }
}

struct QuickActionsCompactView: View {
    let module: QuickActionsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "square.grid.3x2.fill", title: "Quick Actions")
            if module.actions.isEmpty {
                Text("Set up in Settings").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 4)], spacing: 4) {
                    ForEach(module.actions.prefix(8)) { action in
                        IconButton(icon: action.symbol.isEmpty ? "bolt.fill" : action.symbol, size: 10,
                                   help: action.title, tooltipEdge: .top) {
                            module.run(action)
                        }
                    }
                }
            }
        }
    }
}

struct QuickActionsSettingsView: View {
    let module: QuickActionsModule

    var body: some View {
        ForEach(module.actions) { action in
            QuickActionEditor(module: module, action: action)
        }
        HStack {
            Button("Add Action") { module.add() }
            Button("Open Shortcuts") { ShortcutsService.openShortcutsApp() }
            Button("Reload Shortcut List") { Task { await module.refreshShortcutList() } }
        }
        .task { await module.refreshShortcutList() }
        Text("Each button runs one of your Apple Shortcuts. Symbols are SF Symbol names, e.g. “lightbulb.fill”, “moon.fill” or “music.note”.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct QuickActionEditor: View {
    let module: QuickActionsModule
    let action: QuickAction

    private func binding<T>(_ keyPath: WritableKeyPath<QuickAction, T>) -> Binding<T> {
        Binding(
            get: { action[keyPath: keyPath] },
            set: { value in
                var updated = action
                updated[keyPath: keyPath] = value
                module.update(updated)
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.symbol.isEmpty ? "bolt.fill" : action.symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Title", text: binding(\.title))
                    TextField("SF Symbol", text: binding(\.symbol))
                        .frame(width: 130)
                }
                if module.availableShortcuts.isEmpty {
                    TextField("Shortcut name", text: binding(\.shortcut))
                } else {
                    Picker("Shortcut", selection: binding(\.shortcut)) {
                        if !module.availableShortcuts.contains(action.shortcut) {
                            Text(action.shortcut.isEmpty ? "Choose…" : action.shortcut).tag(action.shortcut)
                        }
                        ForEach(module.availableShortcuts, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Button(role: .destructive) { module.remove(action.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this action")
        }
    }
}
