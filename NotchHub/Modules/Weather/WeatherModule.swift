import CoreLocation
import SwiftUI

extension Prefs {
    static let weatherUnit = PrefKey("weather.unit",
                                     Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius")
    static let weatherUseManualLocation = PrefKey("weather.useManualLocation", false)
    static let weatherCity = PrefKey("weather.city", "")
    static let weatherRefreshMinutes = PrefKey("weather.refreshMinutes", 30)
}

/// Current conditions + hourly forecast from Open-Meteo, cached on disk.
@Observable
@MainActor
final class WeatherModule: NotchModule {
    let id = "weather"
    let name = "Weather"
    let icon = "cloud.sun.fill"

    private static let cacheName = "weather-cache.json"

    private(set) var snapshot: WeatherSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var active = false

    init() {
        snapshot = JSONStore.load(WeatherSnapshot.self, from: Self.cacheName)
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(max(5, Prefs.weatherRefreshMinutes.value) * 60)
    }

    private var unit: String { Prefs.weatherUnit.value }

    private var sourceKey: String {
        Prefs.weatherUseManualLocation.value ? "city:\(Prefs.weatherCity.value.lowercased())" : "gps"
    }

    var isStale: Bool {
        guard let snapshot else { return true }
        return snapshot.unit != unit
            || snapshot.sourceKey != sourceKey
            || Date.now.timeIntervalSince(snapshot.fetchedAt) > refreshInterval
    }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        self.active = active
        refreshLoop?.cancel()
        guard active else { return }
        // One cheap wake-up per refresh interval; no polling in between.
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.refreshInterval ?? 1800
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func willExpand() {
        if isStale { Task { await refresh() } }
    }

    // MARK: Fetching

    func refresh(force: Bool = false) async {
        guard active, !isLoading, force || isStale else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let place = try await resolvePlace()
            let snapshot = try await WeatherService.forecast(for: place, unit: unit, sourceKey: sourceKey)
            self.snapshot = snapshot
            errorMessage = nil
            JSONStore.save(snapshot, to: Self.cacheName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvePlace() async throws -> WeatherService.Place {
        let city = Prefs.weatherCity.value.trimmingCharacters(in: .whitespaces)
        if Prefs.weatherUseManualLocation.value, !city.isEmpty {
            return try await WeatherService.geocode(city: city)
        }
        do {
            let location = try await LocationService.shared.currentLocation()
            let name = await LocationService.shared.placeName(for: location) ?? "Current Location"
            return .init(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } catch {
            // Fall back to the manual city if one is set, even when not preferred.
            if !city.isEmpty { return try await WeatherService.geocode(city: city) }
            throw error
        }
    }

    func formatted(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    // MARK: NotchModule

    func compactView() -> AnyView { AnyView(WeatherCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(WeatherExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(WeatherSettingsView(module: self)) }
}
