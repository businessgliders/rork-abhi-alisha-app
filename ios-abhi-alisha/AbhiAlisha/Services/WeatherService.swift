import Foundation

nonisolated struct DayWeather: Sendable, Hashable {
    let highCelsius: Double
    let summary: String
    /// True when the value is a seasonal Cancún average rather than a real forecast.
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

/// Open-Meteo day forecast with a graceful seasonal fallback.
/// Weather must never block a card from rendering, so every failure resolves to the average.
actor WeatherService {
    static let shared = WeatherService()

    private var cache: [String: DayWeather] = [:]

    private let latitude = 21.1619
    private let longitude = -86.8515

    /// Cancún's late-January / early-February norm.
    private let seasonalAverage = DayWeather(highCelsius: 28, summary: "Sunny", isSeasonalAverage: true)

    func weather(for date: Date) async -> DayWeather {
        let key = Self.dayFormatter.string(from: date)
        if let cached = cache[key] { return cached }

        let daysAway = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
        guard daysAway >= -1, daysAway <= 15 else {
            cache[key] = seasonalAverage
            return seasonalAverage
        }

        do {
            let weather = try await fetchForecast(dayKey: key)
            cache[key] = weather
            return weather
        } catch {
            print("[WeatherService] forecast unavailable, using seasonal average")
            cache[key] = seasonalAverage
            return seasonalAverage
        }
    }

    private func fetchForecast(dayKey: String) async throws -> DayWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,weather_code"),
            URLQueryItem(name: "timezone", value: "America/Cancun"),
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
        return DayWeather(highCelsius: high, summary: Self.summary(for: code), isSeasonalAverage: false)
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Cancun")
        return formatter
    }()

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
