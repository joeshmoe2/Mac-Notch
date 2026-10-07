import AppKit
import EventKit

/// One shared EKEventStore for the Calendar and Reminders modules, plus
/// permission state. Changes made in Calendar/Reminders (or synced from
/// iCloud) arrive via `EKEventStoreChanged`, so nothing polls.
@Observable
@MainActor
final class EventKitService {
    static let shared = EventKitService()

    @ObservationIgnored let store = EKEventStore()
    private(set) var eventsStatus: EKAuthorizationStatus
    private(set) var remindersStatus: EKAuthorizationStatus
    /// Incremented whenever the event store reports a change; modules observe it to reload.
    private(set) var changeCount = 0

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        eventsStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { EventKitService.shared.changeCount += 1 }
        }
    }

    var hasEventAccess: Bool { eventsStatus == .fullAccess }
    var hasReminderAccess: Bool { remindersStatus == .fullAccess }
    var eventsDenied: Bool { eventsStatus == .denied || eventsStatus == .restricted || eventsStatus == .writeOnly }
    var remindersDenied: Bool { remindersStatus == .denied || remindersStatus == .restricted || remindersStatus == .writeOnly }

    func refreshStatus() {
        eventsStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    @discardableResult
    func requestEventAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        refreshStatus()
        if granted { changeCount += 1 }
        return granted
    }

    @discardableResult
    func requestReminderAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        refreshStatus()
        if granted { changeCount += 1 }
        return granted
    }

    func openPrivacySettings(reminders: Bool) {
        let pane = reminders ? "Privacy_Reminders" : "Privacy_Calendars"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
