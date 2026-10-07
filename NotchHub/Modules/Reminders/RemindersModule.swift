import AppKit
import EventKit
import SwiftUI

extension Prefs {
    /// Reminder list identifiers the user turned off (comma separated).
    static let remindersHiddenLists = PrefKey("reminders.hiddenLists", "")
    static let remindersHideCompleted = PrefKey("reminders.hideCompleted", true)
    /// List used for quick-add ("" = the default Reminders list).
    static let remindersAddList = PrefKey("reminders.addList", "")
}

/// A snapshot of an EKReminder.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
    let listTitle: String
    let color: NSColor

    var isOverdue: Bool { !isCompleted && (dueDate.map { $0 < .now } ?? false) }
}

/// Reminders from chosen lists: check them off and quick-add new ones.
@Observable
@MainActor
final class RemindersModule: NotchModule {
    let id = "reminders"
    let name = "Reminders"
    let icon = "checklist"

    private(set) var items: [ReminderItem] = []
    private(set) var lastError: String?

    @ObservationIgnored private var active = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var fetchGeneration = 0

    private var service: EventKitService { .shared }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        self.active = active
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard active else { items = []; return }
        // Changes from the Reminders app or iCloud arrive here; no polling.
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppState.shared.module(RemindersModule.self)?.reload() }
        }
        reload()
    }

    func willExpand() {
        service.refreshStatus()
        reload()
    }

    // MARK: Lists

    var allLists: [EKCalendar] {
        guard service.hasReminderAccess else { return [] }
        return service.store.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    private var visibleLists: [EKCalendar] {
        let hidden = Set(Prefs.remindersHiddenLists.value.idList)
        return allLists.filter { !hidden.contains($0.calendarIdentifier) }
    }

    // MARK: Loading

    func reload() {
        guard active, service.hasReminderAccess else {
            items = []
            return
        }
        let lists = visibleLists
        guard !lists.isEmpty else { items = []; return }
        fetchGeneration += 1
        let generation = fetchGeneration
        let hideCompleted = Prefs.remindersHideCompleted.value
        let predicate = hideCompleted
            ? service.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
            // Completed ones from the last week, plus everything still open.
            : service.store.predicateForReminders(in: lists)
        service.store.fetchReminders(matching: predicate) { reminders in
            let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
            let snapshot = (reminders ?? [])
                .filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) > weekAgo }
                .map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        isCompleted: reminder.isCompleted,
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        listTitle: reminder.calendar.title,
                        color: reminder.calendar.color ?? .systemOrange
                    )
                }
                .sorted { a, b in
                    if a.isCompleted != b.isCompleted { return !a.isCompleted }
                    switch (a.dueDate, b.dueDate) {
                    case let (x?, y?): return x < y
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                    }
                }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let module = AppState.shared.module(RemindersModule.self),
                          module.fetchGeneration == generation else { return }
                    if module.items != snapshot { module.items = snapshot }
                }
            }
        }
    }

    // MARK: Editing

    func toggle(_ item: ReminderItem) {
        guard let reminder = service.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        save(reminder)
    }

    func add(title: String, dueDate: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, service.hasReminderAccess else { return }
        let reminder = EKReminder(eventStore: service.store)
        reminder.title = trimmed
        let listID = Prefs.remindersAddList.value
        reminder.calendar = allLists.first { $0.calendarIdentifier == listID }
            ?? service.store.defaultCalendarForNewReminders()
            ?? allLists.first
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        save(reminder)
    }

    private func save(_ reminder: EKReminder) {
        do {
            try service.store.save(reminder, commit: true)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        reload()
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: NotchModule

    func compactView() -> AnyView { AnyView(RemindersCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(RemindersExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(RemindersSettingsView(module: self)) }
}
