import Foundation

/// Fetches weather from the free Open-Meteo API (no API key required).
enum WeatherService {
    enum WeatherError: LocalizedError {
        case cityNotFound(String)
        var errorDescription: String? {
            switch self {
            case .cityNotFound(let city): "Couldn't find \"\(city)\"."
            }
        }
    }

    struct Place {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    static func geocode(city: String) async throws -> Place {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(OpenMeteoGeocoding.self, from: data)
        guard let first = response.results?.first else { throw WeatherError.cityNotFound(city) }
        return Place(name: first.name, latitude: first.latitude, longitude: first.longitude)
    }

    static func forecast(for place: Place, unit: String, sourceKey: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: unit),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)

        let now = Date.now
        var hours: [WeatherSnapshot.Hour] = []
        for (i, time) in forecast.hourly.time.enumerated() {
            let date = Date(timeIntervalSince1970: time)
            guard date > now.addingTimeInterval(-3600),
                  i < forecast.hourly.temperature_2m.count, i < forecast.hourly.weather_code.count else { continue }
            let isDay = (forecast.hourly.is_day?[safe: i] ?? 1) == 1
            hours.append(.init(time: date, temperature: forecast.hourly.temperature_2m[i],
                               weatherCode: forecast.hourly.weather_code[i], isDay: isDay))
            if hours.count == 8 { break }
        }

        return WeatherSnapshot(
            placeName: place.name,
            latitude: place.latitude,
            longitude: place.longitude,
            temperature: forecast.current.temperature_2m,
            weatherCode: forecast.current.weather_code,
            isDay: forecast.current.is_day == 1,
            high: forecast.daily.temperature_2m_max.first ?? forecast.current.temperature_2m,
            low: forecast.daily.temperature_2m_min.first ?? forecast.current.temperature_2m,
            hourly: hours,
            unit: unit,
            sourceKey: sourceKey,
            fetchedAt: now
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
