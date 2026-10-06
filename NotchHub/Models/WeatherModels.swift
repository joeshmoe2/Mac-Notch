import Foundation

struct WeatherSnapshot: Codable, Equatable {
    struct Hour: Codable, Equatable, Identifiable {
        var time: Date
        var temperature: Double
        var weatherCode: Int
        var isDay: Bool
        var id: Date { time }
    }

    var placeName: String
    var latitude: Double
    var longitude: Double
    var temperature: Double
    var weatherCode: Int
    var isDay: Bool
    var high: Double
    var low: Double
    var hourly: [Hour]
    /// "fahrenheit" or "celsius".
    var unit: String
    /// Describes the location source so cached data is invalidated when it changes.
    var sourceKey: String
    var fetchedAt: Date
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing Drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy Rain"
        case 66, 67: "Freezing Rain"
        case 71, 73: "Snow"
        case 75: "Heavy Snow"
        case 77: "Snow Grains"
        case 80, 81: "Showers"
        case 82: "Heavy Showers"
        case 85, 86: "Snow Showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm & Hail"
        default: "Unknown"
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "questionmark.circle"
        }
    }
}

// MARK: - Open-Meteo API payloads

struct OpenMeteoForecast: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    struct Hourly: Decodable {
        let time: [TimeInterval]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let is_day: [Int]?
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

struct OpenMeteoGeocoding: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }
    let results: [Result]?
}
