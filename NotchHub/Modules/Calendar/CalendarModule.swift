import AppKit
import EventKit
import SwiftUI

extension Prefs {
    /// Calendar identifiers the user turned off (comma separated).
    static let calendarHidden = PrefKey("calendar.hidden", "")
    /// How many days to show, starting today (2 = today and tomorrow).
    static let calendarDays = PrefKey("calendar.days", 2)
    /// Show the collapsed countdown this many minutes before an event starts.
    static let calendarLeadMinutes = PrefKey("calendar.leadMinutes", 10)
    static let calendarShowAllDay = PrefKey("calendar.showAllDay", true)
}

/// A snapshot of an EKEvent (EKEvent itself isn't safe to keep around across store changes).
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let calendarTitle: String
    let location: String?
    let meetingURL: URL?

    var meetingService: String? { meetingURL.flatMap(MeetingLinkDetector.serviceName(for:)) }
}

/// Finds Zoom, Google Meet and Microsoft Teams links in an event.
enum MeetingLinkDetector {
    private static let patterns: [NSRegularExpression] = [
        #"(?:https?://[\w.-]*zoom\.us/(?:j|my|w|s|wc/join)/[^\s<>"')\]]+|zoommtg://[^\s<>"')\]]+)"#,
        #"https?://meet\.google\.com/[a-z]{3,}-[a-z]{3,}-[a-z]{3,}[^\s<>"')\]]*"#,
        #"https?://teams\.(?:microsoft|live)\.com/[^\s<>"')\]]+"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func find(in event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            for regex in patterns {
                if let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text),
                   let url = URL(string: String(text[r])) {
                    return url
                }
            }
        }
        return nil
    }

    static func serviceName(for url: URL) -> String? {
        let s = url.absoluteString.lowercased()
        if s.contains("zoom") { return "Zoom" }
        if s.contains("meet.google") { return "Meet" }
        if s.contains("teams.") { return "Teams" }
        return nil
    }
}

/// Today's and upcoming events, with a "next up" countdown in the collapsed notch.
@Observable
@MainActor
final class CalendarModule: NotchModule {
    let id = "calendar"
    let name = "Calendar"
    let icon = "calendar"

    private(set) var events: [CalendarEvent] = []
    /// Advanced only at the moments the live activity needs to change (no polling).
    private(set) var clock = Date.now

    @ObservationIgnored private var active = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var changeObservation: Task<Void, Never>?

    private var service: EventKitService { .shared }
    private static let ongoingGrace: TimeInterval = 5 * 60

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        self.active = active
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        boundaryTask?.cancel()
        guard active else { events = []; return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppState.shared.module(CalendarModule.self)?.reload() }
        })
        // New day (midnight, wake from sleep across midnight, time zone change).
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppState.shared.module(CalendarModule.self)?.reload() }
        })
        reload()
    }

    func willExpand() {
        service.refreshStatus()
        reload()
    }

    // MARK: Loading

    func reload() {
        guard active, service.hasEventAccess else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let days = min(max(Prefs.calendarDays.value, 1), 14)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return }
        let hidden = Set(Prefs.calendarHidden.value.idList)
        let calendars = service.store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { events = []; return }

        let predicate = service.store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let showAllDay = Prefs.calendarShowAllDay.value
        let loaded = service.store.events(matching: predicate)
            .filter { showAllDay || !$0.isAllDay }
            .map { event in
                CalendarEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.color ?? .systemBlue,
                    calendarTitle: event.calendar.title,
                    location: event.location,
                    meetingURL: MeetingLinkDetector.find(in: event)
                )
            }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        if loaded != events { events = loaded }
        clock = .now
        scheduleNextBoundary()
    }

    // MARK: Next up

    /// The next timed event that hasn't finished (still "now" for a few minutes after it starts).
    func nextEvent(at now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && $0.end > now && $0.start.addingTimeInterval(Self.ongoingGrace) > now }
            .min { $0.start < $1.start }
    }

    private var leadTime: TimeInterval { TimeInterval(max(1, Prefs.calendarLeadMinutes.value) * 60) }

    /// Sleeps until the next moment the live activity should appear or change.
    private func scheduleNextBoundary() {
        boundaryTask?.cancel()
        let now = Date.now
        let boundaries = events.filter { !$0.isAllDay }.flatMap { event in
            [event.start.addingTimeInterval(-leadTime), event.start, event.start.addingTimeInterval(Self.ongoingGrace), event.end]
        }
        guard let next = boundaries.filter({ $0 > now }).min() else { return }
        let delay = next.timeIntervalSince(now) + 0.5
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.clock = .now
            self.scheduleNextBoundary()
        }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: NotchModule

    var supportsLiveActivity: Bool { true }

    var liveActivity: LiveActivity? {
        let now = clock
        guard let event = nextEvent(at: now),
              event.start.timeIntervalSince(now) <= leadTime else { return nil }
        let color = Color(nsColor: event.color)
        return LiveActivity(moduleID: id) {
            Image(systemName: event.meetingURL != nil ? "video.fill" : "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        } trailing: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(CalendarFormat.countdown(to: event.start, now: context.date))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    func compactView() -> AnyView { AnyView(CalendarCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(CalendarExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(CalendarSettingsView(module: self)) }
}

enum CalendarFormat {
    /// "in 12m", "in 1h 5m", or "now".
    static func countdown(to date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 30 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
    }

    static func timeRange(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}
