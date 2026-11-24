import Foundation

nonisolated struct DayWeather: Sendable, Hashable {
    let highCelsius: Double
    let summary: String
    /// True when the value is last year's weather on that day rather than a real forecast.
    let isSeasonalAverage: Bool

    /// Short pill text. Always Celsius — the couple's guest list reads in Celsius.
    var pillText: String {
        let degrees = "\(Int(highCelsius.rounded()))°C"
        return isSeasonalAverage ? "Usually \(degrees) · \(summary)" : "\(degrees) · \(summary)"
    }

    /// Just the temperature, for the compact chip on a card. Always Celsius.
    /// A seasonal average is marked with a leading `≈` rather than a word.
    var chipText: String {
        let degrees = "\(Int(highCelsius.rounded()))°"
        return isSeasonalAverage ? "≈\(degrees)" : degrees
    }

    /// Outline SF Symbol matching the day's summary.
    var symbolName: String {
        switch summary {
        case "Clear": return "sun.max"
        case "Sunny": return "sun.max"
        case "Cloudy": return "cloud"
        case "Misty": return "cloud.fog"
        case "Drizzle": return "cloud.drizzle"
        case "Showers": return "cloud.sun.rain"
        case "Rain": return "cloud.rain"
        case "Storms": return "cloud.bolt"
        default: return "sun.haze"
        }
    }

    /// Spoken aloud instead of the glyph and short temperature.
    var accessibilityText: String {
        let degrees = "\(Int(highCelsius.rounded())) degrees Celsius"
        return isSeasonalAverage ? "Usually \(degrees), \(summary)" : "\(degrees), \(summary)"
    }
}

/// Where and when to look up the weather: an event's own spot, else the wedding's.
nonisolated struct WeatherPlace: Sendable, Hashable {
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone

    /// The event's own coordinates when set, otherwise the wedding's; nil when neither is known.
    @MainActor
    static func forEvent(_ event: ScheduleEvent) -> WeatherPlace? {
        let wedding = ActiveWedding.snapshot
        if let lat = event.latitude, let lng = event.longitude, abs(lat) > 0.0001 || abs(lng) > 0.0001 {
            return WeatherPlace(latitude: lat, longitude: lng, timeZone: wedding.timeZone)
        }
        if let lat = wedding.latitude, let lng = wedding.longitude {
            return WeatherPlace(latitude: lat, longitude: lng, timeZone: wedding.timeZone)
        }
        return nil
    }
}

/// Open-Meteo day weather for wherever the wedding is. Within the 16-day forecast window
/// it's a real forecast; further out it's the same date last year at that spot, shown as
/// "Usually". Weather never blocks a card: any failure simply means no weather.
actor WeatherService {
    static let shared = WeatherService()

    private var cache: [String: DayWeather] = [:]
    private var misses: Set<String> = []

    func weather(for date: Date, at place: WeatherPlace) async -> DayWeather? {
        let dayKey = Self.dayKey(date, in: place.timeZone)
        let key = String(format: "%.3f,%.3f,", place.latitude, place.longitude) + dayKey
        if let cached = cache[key] { return cached }
        guard !misses.contains(key) else { return nil }

        let daysAway = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
        let weather: DayWeather?
        if daysAway >= -1, daysAway <= 15 {
            weather = try? await fetch(base: "https://api.open-meteo.com/v1/forecast", dayKey: dayKey, place: place, seasonal: false)
        } else {
            weather = try? await lastYear(date: date, place: place)
        }
        if let weather { cache[key] = weather } else { misses.insert(key) }
        return weather
    }

    /// The same calendar day a year earlier, from Open-Meteo's archive.
    private func lastYear(date: Date, place: WeatherPlace) async throws -> DayWeather {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        var reference = calendar.date(byAdding: .year, value: -1, to: date) ?? date
        // The archive trails real time by a few days; step back another year if needed.
        if reference > Date().addingTimeInterval(-7 * 86_400) {
            reference = calendar.date(byAdding: .year, value: -1, to: reference) ?? reference
        }
        return try await fetch(
            base: "https://archive-api.open-meteo.com/v1/archive",
            dayKey: Self.dayKey(reference, in: place.timeZone),
            place: place,
            seasonal: true
        )
    }

    private func fetch(base: String, dayKey: String, place: WeatherPlace, seasonal: Bool) async throws -> DayWeather {
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,weather_code"),
            URLQueryItem(name: "timezone", value: place.timeZone.identifier),
            URLQueryItem(name: "start_date", value: dayKey),
            URLQueryItem(name: "end_date", value: dayKey)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder().decode(ForecastPayload.self, from: data)
        guard
            let high = payload.daily.temperatureMax.compactMap({ $0 }).first,
            let code = payload.daily.weatherCode.compactMap({ $0 }).first
        else {
            throw URLError(.cannotParseResponse)
        }
        return DayWeather(highCelsius: high, summary: Self.summary(for: code), isSeasonalAverage: seasonal)
    }

    private static func dayKey(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    private static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Sunny"
        case 3: return "Cloudy"
        case 45, 48: return "Misty"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 80, 81, 82: return "Showers"
        case 66, 67: return "Rain"
        case 95, 96, 99: return "Storms"
        default: return "Mild"
        }
    }


    private struct ForecastPayload: Decodable {
        struct Daily: Decodable {
            let temperatureMax: [Double?]
            let weatherCode: [Int?]

            enum CodingKeys: String, CodingKey {
                case temperatureMax = "temperature_2m_max"
                case weatherCode = "weather_code"
            }
        }

        let daily: Daily
    }
}
