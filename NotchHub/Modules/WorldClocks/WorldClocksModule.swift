import SwiftUI

extension Prefs {
    /// Comma separated time zone identifiers, e.g. "Europe/London,Asia/Tokyo".
    static let worldClockZones = PrefKey("worldClocks.zones", "America/New_York,Europe/London,Asia/Tokyo")
}

/// A city clock.
struct WorldClock: Identifiable, Hashable {
    let zone: TimeZone
    var id: String { zone.identifier }

    /// "America/New_York" → "New York".
    var city: String {
        let last = zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    func hour(at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: date)
    }

    /// Simple day/night: 6:00–17:59 is day.
    func isDaytime(at date: Date) -> Bool { (6..<18).contains(hour(at: date)) }

    func time(at date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    /// "Today", "Tomorrow" or "Yesterday" relative to the local date, plus the hour difference.
    func relative(at date: Date) -> String {
        let offsetHours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        var local = Calendar(identifier: .gregorian); local.timeZone = .current
        var remote = Calendar(identifier: .gregorian); remote.timeZone = zone
        let localDay = local.dateComponents([.year, .month, .day], from: date)
        let remoteDay = remote.dateComponents([.year, .month, .day], from: date)
        let dayText: String
        if localDay == remoteDay {
            dayText = "Today"
        } else if let l = local.date(from: localDay), let r = local.date(from: remoteDay) {
            dayText = r > l ? "Tomorrow" : "Yesterday"
        } else {
            dayText = ""
        }
        let sign = offsetHours >= 0 ? "+" : "−"
        let magnitude = abs(offsetHours)
        let offsetText = magnitude == magnitude.rounded() ? "\(Int(magnitude))" : String(format: "%.1f", magnitude)
        return offsetHours == 0 ? dayText : "\(dayText), \(sign)\(offsetText)h"
    }
}

/// Local time in the user's chosen cities. Redraws once a minute via TimelineView.
@Observable
@MainActor
final class WorldClocksModule: NotchModule {
    let id = "worldClocks"
    let name = "World Clocks"
    let icon = "globe"

    private(set) var clocks: [WorldClock] = []

    init() { reload() }

    func reload() {
        clocks = Prefs.worldClockZones.value.idList.compactMap(TimeZone.init(identifier:)).map(WorldClock.init(zone:))
    }

    private func save() {
        Prefs.worldClockZones.set(clocks.map(\.id).joinedIDs)
    }

    func add(_ identifier: String) {
        guard let zone = TimeZone(identifier: identifier), !clocks.contains(where: { $0.id == identifier }) else { return }
        clocks.append(WorldClock(zone: zone))
        save()
    }

    func remove(_ identifier: String) {
        clocks.removeAll { $0.id == identifier }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        clocks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func willExpand() { reload() }

    func compactView() -> AnyView { AnyView(WorldClocksCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(WorldClocksExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(WorldClocksSettingsView(module: self)) }
}

struct WorldClocksExpandedView: View {
    let module: WorldClocksModule

    var body: some View {
        if module.clocks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Add cities in Settings.").foregroundStyle(.secondary)
                Button("Add Cities") { SettingsOpener.open(page: .module(module.id)) }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Once a minute is all a clock showing hours and minutes needs.
            TimelineView(.everyMinute) { context in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(module.clocks) { clock in
                            ClockCard(clock: clock, date: context.date)
                        }
                    }
                }
            }
        }
    }
}

private struct ClockCard: View {
    let clock: WorldClock
    let date: Date

    var body: some View {
        let day = clock.isDaytime(at: date)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(clock.city).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Image(systemName: day ? "sun.max.fill" : "moon.stars.fill")
                    .foregroundStyle(day ? Color.yellow : Color.indigo)
                    .accessibilityLabel(day ? "Daytime" : "Night")
            }
            Text(clock.time(at: date))
                .font(.system(size: 22, weight: .light).monospacedDigit())
            Text(clock.relative(at: date)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(day ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }
}

struct WorldClocksCompactView: View {
    let module: WorldClocksModule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModuleTileHeader(icon: "globe", title: "World Clocks")
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(module.clocks.prefix(4)) { clock in
                        HStack(spacing: 4) {
                            Image(systemName: clock.isDaytime(at: context.date) ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(clock.isDaytime(at: context.date) ? Color.yellow : Color.indigo)
                            Text(clock.city).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(clock.time(at: context.date)).monospacedDigit()
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            if module.clocks.isEmpty {
                Text("Add cities in Settings").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorldClocksSettingsView: View {
    let module: WorldClocksModule
    @State private var search = ""

    /// All known zones whose city or region matches the search.
    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.replacingOccurrences(of: "_", with: " ").localizedStandardContains(query) }
            .filter { id in !module.clocks.contains { $0.id == id } }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        ForEach(module.clocks) { clock in
            HStack {
                Text(clock.city)
                Text(clock.zone.identifier).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    module.remove(clock.id)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(clock.city)")
            }
        }
        TextField("Add a city", text: $search, prompt: Text("Search, e.g. Paris or Sydney"))
        ForEach(matches, id: \.self) { identifier in
            Button {
                module.add(identifier)
                search = ""
            } label: {
                Label(identifier.replacingOccurrences(of: "_", with: " "), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        Text("Cities come from the system's time zone list, so smaller towns appear under their region's main city.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
