import EventKit
import SwiftUI

/// Shown when calendar or reminders access hasn't been granted.
struct EventKitPermissionView: View {
    let reminders: Bool
    /// Extra button under the main one (e.g. "Link Google Calendar…").
    var secondary: (title: String, action: () -> Void)? = nil
    let onGranted: () -> Void
    private var service: EventKitService { .shared }

    private var denied: Bool { reminders ? service.remindersDenied : service.eventsDenied }
    private var what: String { reminders ? "Reminders" : "Calendar" }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: reminders ? "checklist" : "calendar.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            if denied {
                Text("NotchHub doesn't have access to your \(what.lowercased()).")
                    .foregroundStyle(.secondary)
                Button("Open \(what) Privacy Settings") { service.openPrivacySettings(reminders: reminders) }
                    .buttonStyle(PillButtonStyle())
                Text("Turn on NotchHub there, then reopen the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Show your \(what.lowercased()) in the notch.")
                    .foregroundStyle(.secondary)
                Button("Allow \(what) Access") {
                    Task {
                        let granted = reminders ? await service.requestReminderAccess() : await service.requestEventAccess()
                        if granted { onGranted() }
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
            if let secondary {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CalendarExpandedView: View {
    let module: CalendarModule
    private var service: EventKitService { .shared }

    private struct DaySection: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    private var days: [DaySection] {
        let calendar = Calendar.current
        // Events that started before today (multi-day) are listed under today.
        let grouped = Dictionary(grouping: module.events) { calendar.startOfDay(for: max($0.start, calendar.startOfDay(for: .now))) }
        return grouped.keys.sorted().map { DaySection(day: $0, events: grouped[$0] ?? []) }
    }

    var body: some View {
        if !module.hasAnySource {
            EventKitPermissionView(reminders: false, secondary: (title: "Link Google Calendar…", action: {
                SettingsOpener.open(page: .module(module.id))
            })) { module.reload() }
        } else if module.events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Nothing scheduled").foregroundStyle(.secondary)
                Button("Open Calendar") { module.openCalendarApp() }.buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.events) { event in
                                EventRow(module: module, event: event)
                            }
                        } header: {
                            Text(CalendarFormat.dayTitle(day.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                        }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let module: CalendarModule
    let event: CalendarEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isNow = !event.isAllDay && event.start <= context.date && event.end > context.date
            let isPast = event.end <= context.date
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(CalendarFormat.timeRange(event))
                        if let location = event.location, !location.isEmpty, event.meetingURL == nil {
                            Text("· \(location)").lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isNow {
                    Text("Now").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                } else if !event.isAllDay && !isPast && event.start.timeIntervalSince(context.date) < 3 * 3600 {
                    Text(CalendarFormat.countdown(to: event.start, now: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let url = event.meetingURL, !isPast {
                    Button {
                        module.open(url)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .tooltip("Join \(event.meetingService ?? "meeting")")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isNow ? 0.12 : 0.05)))
            .opacity(isPast ? 0.45 : 1)
        }
    }
}

struct CalendarCompactView: View {
    let module: CalendarModule
    private var service: EventKitService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "calendar", title: "Next Up")
            if !module.hasAnySource {
                Text("Allow access in the Calendar tab").font(.caption).foregroundStyle(.secondary)
            } else if let next = module.nextEvent(at: module.clock) {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: next.color)).frame(width: 7, height: 7)
                    Text(next.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(Calendar.current.isDateInToday(next.start)
                         ? CalendarFormat.countdown(to: next.start, now: context.date)
                         : CalendarFormat.dayTitle(next.start) + " " + next.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = next.meetingURL {
                    Button("Join") { module.open(url) }.buttonStyle(PillButtonStyle(prominent: true))
                }
            } else {
                Text("Nothing else today").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CalendarSettingsView: View {
    let module: CalendarModule
    @AppStorage(Prefs.calendarHidden) private var hidden
    @AppStorage(Prefs.calendarDays) private var days
    @AppStorage(Prefs.calendarLeadMinutes) private var leadMinutes
    @AppStorage(Prefs.calendarShowAllDay) private var showAllDay
    private var service: EventKitService { .shared }

    var body: some View {
        if service.hasEventAccess {
            let calendars = service.store.calendars(for: .event)
                .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                Toggle(isOn: Binding(
                    get: { !hidden.idList.contains(calendar.calendarIdentifier) },
                    set: { show in
                        var list = hidden.idList.filter { $0 != calendar.calendarIdentifier }
                        if !show { list.append(calendar.calendarIdentifier) }
                        hidden = list.joinedIDs
                        module.reload()
                    }
                )) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: calendar.color ?? .systemBlue)).frame(width: 9, height: 9)
                        Text(calendar.title)
                        Text(calendar.source.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            LabeledContent("Calendar access") {
                Button(service.eventsDenied ? "Open Privacy Settings" : "Allow Access") {
                    if service.eventsDenied {
                        service.openPrivacySettings(reminders: false)
                    } else {
                        Task { if await service.requestEventAccess() { module.reload() } }
                    }
                }
            }
        }
        Stepper("Show \(days) day\(days == 1 ? "" : "s") (from today)", value: $days, in: 1...14)
            .onChange(of: days) { module.reload() }
        Picker("Show countdown in the collapsed notch", selection: $leadMinutes) {
            ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes before").tag($0) }
        }
        .onChange(of: leadMinutes) { module.reload() }
        Toggle("Show all-day events", isOn: $showAllDay)
            .onChange(of: showAllDay) { module.reload() }
        Text("Zoom, Google Meet and Microsoft Teams links in an event get a Join button.")
            .font(.caption)
            .foregroundStyle(.secondary)
        GoogleCalendarSettings(module: module)
    }
}

/// Two ways to see Google Calendar without signing in to Google inside NotchHub.
private struct GoogleCalendarSettings: View {
    let module: CalendarModule
    private var feeds: ICalFeedService { .shared }

    var body: some View {
        Group {
            Text("Google Calendar").font(.headline).padding(.top, 6)
            LabeledContent("Best: add your Google account to the Mac") {
                Button("Open Internet Accounts") { openInternetAccounts() }
            }
            Text("System Settings → Internet Accounts → Add Account → Google, and turn on Calendars. Your Google calendars then show up in the list above (and in Apple Calendar), with no extra setup here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(feeds.feeds) { feed in
                ICalFeedEditor(module: module, feed: feed)
            }
            HStack {
                Button("Add Google Calendar Link") { feeds.add() }
                Button("Open Google Calendar Settings") {
                    if let url = URL(string: "https://calendar.google.com/calendar/r/settings") { NSWorkspace.shared.open(url) }
                }
                if !feeds.feeds.isEmpty {
                    Button("Refresh Now") { module.refreshFeeds() }
                }
            }
            Text("Or link one calendar: in Google Calendar on the web open Settings, click the calendar on the left, scroll to \"Integrate calendar\" and copy the \"Secret address in iCal format\". Linked calendars are read-only and refresh every 30 minutes. Keep the link private: anyone who has it can see that calendar. School accounts sometimes hide this option; use Internet Accounts instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openInternetAccounts() {
        let urls = ["x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
                    "x-apple.systempreferences:com.apple.preferences.internetaccounts"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct ICalFeedEditor: View {
    let module: CalendarModule
    let feed: ICalFeed
    private var feeds: ICalFeedService { .shared }

    private func binding<T>(_ keyPath: WritableKeyPath<ICalFeed, T>) -> Binding<T> {
        Binding(
            get: { feed[keyPath: keyPath] },
            set: { value in
                var updated = feed
                updated[keyPath: keyPath] = value
                feeds.update(updated)
                module.reload()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: binding(\.enabled)).labelsHidden()
                    .help("Show this calendar")
                ColorPicker("", selection: Binding(
                    get: { Color(hex: feed.colorHex) ?? .blue },
                    set: { binding(\.colorHex).wrappedValue = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                .help("Calendar color")
                TextField("Name", text: binding(\.name))
                    .frame(width: 150)
                TextField("https://calendar.google.com/calendar/ical/…/basic.ics", text: binding(\.url))
                    .onSubmit { module.refreshFeeds() }
                Button(role: .destructive) {
                    feeds.remove(feed.id)
                    module.reload()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this calendar link")
            }
            if let error = feeds.errors[feed.id] {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else if let events = feeds.parsed[feed.id] {
                Text("Linked · \(events.count) event\(events.count == 1 ? "" : "s") loaded")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !feed.url.isEmpty {
                Text("Press Return or Refresh Now to load it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
