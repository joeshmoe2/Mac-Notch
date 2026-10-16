import AppKit
import SwiftUI

extension Prefs {
    /// JSON-encoded [QuickAction].
    static let quickActionsItems = PrefKey("quickActions.items", "[]")
}

struct QuickAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    /// SF Symbol name.
    var symbol: String
    /// Name of the Apple Shortcut to run.
    var shortcut: String
    /// When set, the button opens this link (e.g. a Google app) instead of running a shortcut.
    var url: String?

    var isLink: Bool { url != nil }

    var linkURL: URL? {
        guard let text = url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return URL(string: text.contains("://") ? text : "https://" + text)
    }
}

/// Ready-made links for Google's web apps.
enum GoogleAppLink: String, CaseIterable, Identifiable {
    case gmail, calendar, drive, docs, sheets, slides, classroom, tasks, keep, meet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmail: "Gmail"
        case .calendar: "Google Calendar"
        case .drive: "Google Drive"
        case .docs: "Google Docs"
        case .sheets: "Google Sheets"
        case .slides: "Google Slides"
        case .classroom: "Google Classroom"
        case .tasks: "Google Tasks"
        case .keep: "Google Keep"
        case .meet: "Google Meet"
        }
    }

    /// Short label for the tile.
    var shortTitle: String {
        self == .gmail ? "Gmail" : String(title.dropFirst("Google ".count))
    }

    var symbol: String {
        switch self {
        case .gmail: "envelope.fill"
        case .calendar: "calendar"
        case .drive: "externaldrive.fill"
        case .docs: "doc.text.fill"
        case .sheets: "tablecells.fill"
        case .slides: "rectangle.on.rectangle"
        case .classroom: "graduationcap.fill"
        case .tasks: "checkmark.circle.fill"
        case .keep: "lightbulb.fill"
        case .meet: "video.fill"
        }
    }

    var url: String {
        switch self {
        case .gmail: "https://mail.google.com/"
        case .calendar: "https://calendar.google.com/"
        case .drive: "https://drive.google.com/"
        case .docs: "https://docs.google.com/document/"
        case .sheets: "https://docs.google.com/spreadsheets/"
        case .slides: "https://docs.google.com/presentation/"
        case .classroom: "https://classroom.google.com/"
        case .tasks: "https://tasks.google.com/"
        case .keep: "https://keep.google.com/"
        case .meet: "https://meet.google.com/"
        }
    }
}

/// A grid of buttons that each run an Apple Shortcut or open a link (e.g. a Google app).
@Observable
@MainActor
final class QuickActionsModule: NotchModule {
    let id = "quickActions"
    let name = "Quick Actions"
    let icon = "square.grid.3x2.fill"

    enum RunState: Equatable { case running, succeeded, failed(String) }

    private(set) var actions: [QuickAction] = []
    private(set) var states: [UUID: RunState] = [:]
    /// The user's shortcut names (loaded on demand for the settings picker).
    private(set) var availableShortcuts: [String] = []

    init() {
        load()
    }

    // MARK: Storage (typed settings key, so it's included in settings export/import)

    func load() {
        let data = Data(Prefs.quickActionsItems.value.utf8)
        actions = (try? JSONDecoder().decode([QuickAction].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(actions), let json = String(data: data, encoding: .utf8) else { return }
        Prefs.quickActionsItems.set(json)
    }

    func add() {
        actions.append(QuickAction(title: "New Action", symbol: "bolt.fill", shortcut: availableShortcuts.first ?? ""))
        save()
    }

    func addLink(_ app: GoogleAppLink? = nil) {
        actions.append(QuickAction(title: app?.shortTitle ?? "New Link", symbol: app?.symbol ?? "link",
                                   shortcut: "", url: app?.url ?? "https://"))
        save()
    }

    func update(_ action: QuickAction) {
        guard let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[i] = action
        save()
    }

    func remove(_ id: UUID) {
        actions.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        actions.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func refreshShortcutList() async {
        availableShortcuts = await ShortcutsService.list()
    }

    // MARK: Running

    func run(_ action: QuickAction) {
        if action.isLink {
            guard let url = action.linkURL, NSWorkspace.shared.open(url) else {
                states[action.id] = .failed("That link couldn't be opened.")
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    states[action.id] = nil
                }
                return
            }
            AppState.shared.collapseNotch()
            return
        }
        guard states[action.id] != .running else { return }
        states[action.id] = .running
        Task {
            let result = await ShortcutsService.run(action.shortcut)
            switch result {
            case .success: states[action.id] = .succeeded
            case .failure(let error): states[action.id] = .failed(error.message)
            }
            // Clear the ✓ / ✕ badge after a moment.
            try? await Task.sleep(for: .seconds(result.isSuccess ? 2 : 6))
            if states[action.id] != .running { states[action.id] = nil }
        }
    }

    func willExpand() {
        // Pick up changes made by settings import/reset.
        load()
    }

    // MARK: NotchModule

    func compactView() -> AnyView { AnyView(QuickActionsCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(QuickActionsExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(QuickActionsSettingsView(module: self)) }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}
