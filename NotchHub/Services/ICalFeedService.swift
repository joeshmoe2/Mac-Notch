import AppKit
import Foundation

extension Prefs {
    /// JSON-encoded [ICalFeed]: calendars subscribed by link (e.g. Google Calendar's
    /// "Secret address in iCal format"). Stored as a typed key so it's exported with settings.
    static let calendarFeeds = PrefKey("calendar.feeds", "[]")
}

/// A calendar subscribed by its iCal (.ics) link.
struct ICalFeed: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var colorHex: String = "#4285F4"
    var enabled = true

    /// `webcal://` links are plain HTTPS underneath.
    var fetchURL: URL? {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

/// Downloads and parses iCal feeds. Refreshes only when asked (on expand, at most
/// every few minutes) and on a slow timer while the Calendar module is active.
@Observable
@MainActor
final class ICalFeedService {
    static let shared = ICalFeedService()

    private(set) var feeds: [ICalFeed] = []
    /// Parsed events per feed.
    private(set) var parsed: [UUID: [ICalEvent]] = [:]
    /// Last error per feed, shown in settings.
    private(set) var errors: [UUID: String] = [:]
    private(set) var lastRefresh: Date?
    @ObservationIgnored private var refreshing = false

    private init() {
        load()
    }

    // MARK: Storage

    func load() {
        let data = Data(Prefs.calendarFeeds.value.utf8)
        let loaded = (try? JSONDecoder().decode([ICalFeed].self, from: data)) ?? []
        if loaded != feeds { feeds = loaded }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(feeds), let json = String(data: data, encoding: .utf8) else { return }
        Prefs.calendarFeeds.set(json)
    }

    func add() {
        let colors = ["#4285F4", "#0B8043", "#D50000", "#F4511E", "#8E24AA", "#F6BF26"]
        feeds.append(ICalFeed(name: "Google Calendar", url: "", colorHex: colors[feeds.count % colors.count]))
        save()
    }

    func update(_ feed: ICalFeed) {
        guard let i = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let urlChanged = feeds[i].url != feed.url
        feeds[i] = feed
        save()
        if urlChanged {
            parsed[feed.id] = nil
            errors[feed.id] = nil
        }
    }

    func remove(_ id: UUID) {
        feeds.removeAll { $0.id == id }
        parsed[id] = nil
        errors[id] = nil
        save()
    }

    var hasActiveFeeds: Bool { feeds.contains { $0.enabled && $0.fetchURL != nil } }

    // MARK: Fetching

    /// Refreshes all feeds if the last refresh is older than `maxAge`.
    func refreshIfStale(maxAge: TimeInterval = 5 * 60) async {
        load()
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < maxAge,
           feeds.allSatisfy({ !$0.enabled || parsed[$0.id] != nil || errors[$0.id] != nil }) {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        lastRefresh = .now
        for feed in feeds where feed.enabled {
            guard let url = feed.fetchURL else {
                errors[feed.id] = feed.url.isEmpty ? nil : "That doesn't look like a calendar link."
                continue
            }
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("text/calendar", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw FeedError.http(http.statusCode)
                }
                let events = try await Task.detached(priority: .utility) {
                    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                          text.contains("BEGIN:VCALENDAR") else { throw FeedError.notICal }
                    return ICalParser.parse(text)
                }.value
                parsed[feed.id] = events
                errors[feed.id] = nil
            } catch let error as FeedError {
                errors[feed.id] = error.message
            } catch {
                errors[feed.id] = "Couldn't download: \(error.localizedDescription)"
            }
        }
    }

    /// Event occurrences from all enabled feeds overlapping `start..<end`.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        feeds.filter(\.enabled).flatMap { feed -> [CalendarEvent] in
            let color = NSColor(hex: feed.colorHex) ?? .systemBlue
            return (parsed[feed.id] ?? []).flatMap { event in
                event.occurrences(from: start, to: end).map { occurrence in
                    CalendarEvent(
                        id: "\(feed.id.uuidString)|\(event.uid)|\(occurrence.start.timeIntervalSince1970)",
                        title: event.summary.isEmpty ? "Untitled" : event.summary,
                        start: occurrence.start,
                        end: occurrence.end,
                        isAllDay: event.isAllDay,
                        color: color,
                        calendarTitle: feed.name,
                        location: event.location,
                        meetingURL: MeetingLinkDetector.find(inTexts: [event.url, event.location, event.description].compactMap { $0 })
                    )
                }
            }
        }
    }

    enum FeedError: Error {
        case http(Int)
        case notICal

        var message: String {
            switch self {
            case .http(404): "Link not found (404). If you reset the secret address in Google Calendar, paste the new one."
            case .http(let code) where code == 401 || code == 403:
                "Google refused the link (\(code)). Use the \"Secret address in iCal format\", not the public one."
            case .http(let code): "The server answered with error \(code)."
            case .notICal: "That link isn't an iCal calendar. Use the address ending in .ics."
            }
        }
    }
}

// MARK: - Parsing

/// One VEVENT, possibly recurring.
struct ICalEvent: Sendable {
    var uid = UUID().uuidString
    var summary = ""
    var location: String?
    var description: String?
    var url: String?
    var start: Date = .distantPast
    var end: Date?
    var duration: TimeInterval?
    var isAllDay = false
    var timeZone: TimeZone = .current
    var rule: RecurrenceRule?
    var exceptions: Set<Date> = []
    /// Replaced occurrences (from events with RECURRENCE-ID), keyed by original start.
    var overrides: [Date: ICalEvent] = [:]
    var recurrenceID: Date?
    var cancelled = false

    var length: TimeInterval {
        if let end { return max(0, end.timeIntervalSince(start)) }
        if let duration { return duration }
        return isAllDay ? 86_400 : 0
    }

    struct Occurrence { let start: Date; let end: Date }

    func occurrences(from windowStart: Date, to windowEnd: Date) -> [Occurrence] {
        guard !cancelled else { return [] }
        let length = self.length
        func overlaps(_ s: Date) -> Bool { s < windowEnd && s.addingTimeInterval(max(length, 1)) > windowStart }

        guard let rule else {
            return overlaps(start) ? [Occurrence(start: start, end: start.addingTimeInterval(length))] : []
        }
        var result: [Occurrence] = []
        for s in rule.starts(from: start, timeZone: isAllDay ? .current : timeZone,
                                  windowStart: windowStart.addingTimeInterval(-max(length, 0)), until: windowEnd)
        where !exceptions.contains(s) {
            if let replacement = overrides[s] {
                if !replacement.cancelled, overlaps(replacement.start) {
                    result.append(Occurrence(start: replacement.start, end: replacement.start.addingTimeInterval(replacement.length)))
                }
            } else if overlaps(s) {
                result.append(Occurrence(start: s, end: s.addingTimeInterval(length)))
            }
        }
        // Overrides moved into the window from an occurrence outside it.
        for (original, replacement) in overrides where !replacement.cancelled && !overlaps(original) && overlaps(replacement.start) {
            result.append(Occurrence(start: replacement.start, end: replacement.start.addingTimeInterval(replacement.length)))
        }
        return result
    }
}

/// The subset of RFC 5545 RRULE that calendars like Google actually produce.
struct RecurrenceRule: Sendable {
    enum Frequency: String, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }
    var frequency: Frequency
    var interval = 1
    var count: Int?
    var until: Date?
    /// Weekdays (1 = Sunday … 7 = Saturday), for weekly rules.
    var byWeekday: [Int] = []

    init?(_ text: String) {
        var parts: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[String(kv[0]).uppercased()] = String(kv[1]) }
        }
        guard let freq = parts["FREQ"].flatMap({ Frequency(rawValue: $0.uppercased()) }) else { return nil }
        frequency = freq
        interval = max(1, Int(parts["INTERVAL"] ?? "") ?? 1)
        count = parts["COUNT"].flatMap { Int($0) }
        until = parts["UNTIL"].flatMap { ICalParser.date($0, params: [:]).date }
        let days = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        byWeekday = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { days[String($0.suffix(2)).uppercased()] }
    }

    /// Occurrence starts from `first` up to `limit` (honouring COUNT and UNTIL).
    /// Without COUNT, whole periods before `windowStart` are skipped so old
    /// recurring events (e.g. a weekly class since 2019) stay cheap.
    func starts(from first: Date, timeZone: TimeZone, windowStart: Date, until limit: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = min(limit, until.map { $0.addingTimeInterval(1) } ?? .distantFuture)
        var result: [Date] = []
        var produced = 0
        let maxIterations = 20_000

        func emit(_ date: Date) -> Bool {
            guard date >= first else { return true }
            guard date < end else { return false }
            if let count, produced >= count { return false }
            produced += 1
            result.append(date)
            return true
        }

        // Conservative (never too many) estimate of whole periods to skip.
        let shortestPeriod: TimeInterval = switch frequency {
        case .daily: 86_400 + 3_600
        case .weekly: 604_800 + 3_600
        case .monthly: 31 * 86_400
        case .yearly: 366 * 86_400
        }
        let skipPeriods = count == nil
            ? max(0, Int(windowStart.timeIntervalSince(first) / (shortestPeriod * Double(interval))) - 2)
            : 0

        if frequency == .weekly && !byWeekday.isEmpty {
            let firstWeekday = calendar.component(.weekday, from: first)
            let time = calendar.dateComponents([.hour, .minute, .second], from: first)
            guard let weekStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: calendar.startOfDay(for: first)) else { return [] }
            let weekdays = byWeekday.sorted()
            for week in skipPeriods..<(skipPeriods + maxIterations) {
                guard let thisWeek = calendar.date(byAdding: .weekOfYear, value: week * interval, to: weekStart) else { break }
                if thisWeek >= end { break }
                for weekday in weekdays {
                    guard let day = calendar.date(byAdding: .day, value: weekday - 1, to: thisWeek),
                          let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                   second: time.second ?? 0, of: day) else { continue }
                    if !emit(date) { return result }
                }
            }
            return result
        }

        let component: Calendar.Component = switch frequency {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        for i in skipPeriods..<(skipPeriods + maxIterations) {
            // Always add to the original start so e.g. the 31st doesn't drift to the 28th.
            guard let date = calendar.date(byAdding: component, value: i * interval, to: first) else { break }
            if !emit(date) { break }
        }
        return result
    }
}

enum ICalParser {
    static func parse(_ text: String) -> [ICalEvent] {
        // Unfold continuation lines (CRLF followed by a space or tab).
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }

        var events: [ICalEvent] = []
        var current: ICalEvent?
        var depth = 0 // nested components inside a VEVENT (VALARM)
        for line in lines {
            if line == "BEGIN:VEVENT" { current = ICalEvent(); depth = 0; continue }
            guard var event = current else { continue }
            if line.hasPrefix("BEGIN:") { depth += 1; continue }
            if line.hasPrefix("END:") {
                if depth > 0 { depth -= 1; continue }
                if line == "END:VEVENT" { events.append(event); current = nil }
                continue
            }
            guard depth == 0, let colon = colonIndex(in: line) else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let headParts = head.split(separator: ";")
            let name = headParts.first.map { String($0).uppercased() } ?? ""
            var params: [String: String] = [:]
            for p in headParts.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { params[String(kv[0]).uppercased()] = String(kv[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            switch name {
            case "UID": event.uid = value
            case "SUMMARY": event.summary = unescape(value)
            case "LOCATION": event.location = unescape(value)
            case "DESCRIPTION": event.description = unescape(value)
            case "URL": event.url = value
            case "STATUS": event.cancelled = value.uppercased() == "CANCELLED"
            case "DTSTART":
                let parsed = date(value, params: params)
                if let d = parsed.date { event.start = d }
                event.isAllDay = parsed.allDay
                if let tz = parsed.timeZone { event.timeZone = tz }
            case "DTEND": event.end = date(value, params: params).date
            case "DURATION": event.duration = duration(value)
            case "RRULE": event.rule = RecurrenceRule(value)
            case "EXDATE":
                for part in value.split(separator: ",") {
                    if let d = date(String(part), params: params).date { event.exceptions.insert(d) }
                }
            case "RECURRENCE-ID": event.recurrenceID = date(value, params: params).date
            default: break
            }
            current = event
        }

        // Attach modified occurrences to their recurring parent.
        var byUID: [String: Int] = [:]
        var result: [ICalEvent] = []
        var overrides: [ICalEvent] = []
        for event in events {
            if event.recurrenceID != nil { overrides.append(event); continue }
            byUID[event.uid] = result.count
            result.append(event)
        }
        for override in overrides {
            if let i = byUID[override.uid], let original = override.recurrenceID, result[i].rule != nil {
                result[i].overrides[original] = override
            } else {
                result.append(override)
            }
        }
        return result
    }

    /// The colon separating name/params from the value, skipping colons inside quoted params.
    private static func colonIndex(in line: String) -> String.Index? {
        var quoted = false
        for i in line.indices {
            switch line[i] {
            case "\"": quoted.toggle()
            case ":" where !quoted: return i
            default: continue
            }
        }
        return nil
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Parses `20261016`, `20261016T150000` (floating or with TZID) and `20261016T150000Z`.
    static func date(_ value: String, params: [String: String]) -> (date: Date?, allDay: Bool, timeZone: TimeZone?) {
        let v = value.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if params["VALUE"]?.uppercased() == "DATE" || (v.count == 8 && !v.contains("T")) {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return (formatter.date(from: String(v.prefix(8))), true, nil)
        }
        if v.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return (formatter.date(from: v), false, nil)
        }
        let tz = params["TZID"].flatMap { TimeZone(identifier: $0) }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = tz ?? .current
        return (formatter.date(from: v), false, tz)
    }

    /// Parses an ISO 8601 duration such as `PT1H30M` or `P1D`.
    static func duration(_ value: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        for ch in value.uppercased() {
            switch ch {
            case "P", "+": continue
            case "-": return nil
            case "T": inTime = true
            case "0"..."9": number.append(ch)
            default:
                let n = Double(number) ?? 0
                number = ""
                switch ch {
                case "W": total += n * 604_800
                case "D": total += n * 86_400
                case "H" where inTime: total += n * 3_600
                case "M" where inTime: total += n * 60
                case "S" where inTime: total += n
                default: return nil
                }
            }
        }
        return total
    }
}
