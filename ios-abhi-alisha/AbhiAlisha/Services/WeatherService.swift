import CoreLocation
import Foundation
import WeatherKit

/// One event's weather, from Apple Weather. Within ten days it's the forecast for the hour
/// the event starts; further out it's the long-term average for that day of the year.
nonisolated struct DayWeather: Sendable, Hashable {
    let highCelsius: Double
    let summary: String
    /// True when the value is the long-term average for that day rather than a real forecast.
    let isSeasonalAverage: Bool
    /// The SF Symbol Apple Weather picked for the hour.
    var conditionSymbol: String? = nil
    /// "Bring an umbrella" or "Sun cream", when the forecast calls for it.
    var hint: String? = nil

    /// Short pill text. Always Celsius — the guest lists read in Celsius.
    var pillText: String {
        let degrees = "\(Int(highCelsius.rounded()))°"
        return isSeasonalAverage
            ? String(localized: "Usually \(degrees) · \(summary)")
            : "\(degrees) · \(summary)"
    }

    /// Just the temperature, for the compact chip on a card. A seasonal average is marked
    /// with a leading `≈` rather than a word.
    var chipText: String {
        let degrees = "\(Int(highCelsius.rounded()))°"
        return isSeasonalAverage ? "≈\(degrees)" : degrees
    }

    var symbolName: String {
        if let conditionSymbol { return conditionSymbol }
        switch summary {
        case "Mostly dry": return "sun.max"
        case "Some showers": return "cloud.sun.rain"
        case "Often rainy": return "cloud.rain"
        default: return "sun.haze"
        }
    }

    /// Spoken aloud instead of the glyph and short temperature.
    var accessibilityText: String {
        let degrees = "\(Int(highCelsius.rounded())) degrees Celsius"
        var text = isSeasonalAverage ? String(localized: "Usually \(degrees), \(summary)") : "\(degrees), \(summary)"
        if let hint { text += ". \(hint)" }
        return text
    }

    var shelfChip: WeatherChipShelf.Chip {
        WeatherChipShelf.Chip(text: pillText, symbol: symbolName, accessibility: accessibilityText, fetchedAt: Date())
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
        return forWedding()
    }

    @MainActor
    static func forWedding() -> WeatherPlace? {
        let wedding = ActiveWedding.snapshot
        guard let lat = wedding.latitude, let lng = wedding.longitude else { return nil }
        return WeatherPlace(latitude: lat, longitude: lng, timeZone: wedding.timeZone)
    }
}

/// Apple Weather's required mark and legal link, fetched once.
nonisolated struct WeatherCredit: Sendable, Hashable {
    let lightMarkURL: URL
    let darkMarkURL: URL
    let legalURL: URL
    let serviceName: String
}

/// Apple Weather for the wedding. Only outdoor events ask; each answer is kept for an hour.
/// Weather never blocks a screen: any failure simply means no chip.
actor WeddingWeather {
    static let shared = WeddingWeather()

    private struct Entry { let weather: DayWeather?; let at: Date }
    private var cache: [String: Entry] = [:]
    private var credit: WeatherCredit?

    /// Weather for an event (or the wedding, with a stable key like "wedding").
    func weather(key: String, for date: Date, at place: WeatherPlace) async -> DayWeather? {
        let cacheKey = key + "@" + String(Int(date.timeIntervalSince1970))
        if let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < 3600 { return hit.weather }

        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let untilStart = date.timeIntervalSinceNow
        let result: DayWeather?
        if untilStart < -3 * 3600 {
            result = nil
        } else if untilStart < 10 * 86_400 {
            result = await hourly(at: date, location: location)
        } else {
            result = await usual(on: date, location: location)
        }
        cache[cacheKey] = Entry(weather: result, at: Date())
        return result
    }

    func attribution() async -> WeatherCredit? {
        if let credit { return credit }
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        let made = WeatherCredit(
            lightMarkURL: attribution.combinedMarkLightURL,
            darkMarkURL: attribution.combinedMarkDarkURL,
            legalURL: attribution.legalPageURL,
            serviceName: attribution.serviceName
        )
        credit = made
        return made
    }

    private func hourly(at date: Date, location: CLLocation) async -> DayWeather? {
        let start = date.addingTimeInterval(-3600)
        let end = date.addingTimeInterval(3600)
        guard let forecast = try? await WeatherService.shared.weather(
            for: location,
            including: .hourly(startDate: max(start, Date().addingTimeInterval(-3600)), endDate: end)
        ) else { return nil }
        guard let hour = forecast.forecast.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return nil }

        var hint: String?
        if hour.precipitationChance > 0.4 {
            hint = String(localized: "Bring an umbrella")
        } else if hour.uvIndex.value >= 7 {
            hint = String(localized: "Sun cream")
        }
        return DayWeather(
            highCelsius: hour.temperature.converted(to: .celsius).value,
            summary: hour.condition.description,
            isSeasonalAverage: false,
            conditionSymbol: hour.symbolName,
            hint: hint
        )
    }

    /// The long-term average for that day of the year (iOS 18 daily statistics).
    private func usual(on date: Date, location: CLLocation) async -> DayWeather? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let day = utc.ordinality(of: .day, in: .year, for: date) else { return nil }
        guard let (precipitation, temperature) = try? await WeatherService.shared.dailyStatistics(
            for: location, startDay: day, endDay: day, including: .precipitation, .temperature
        ), let temp = temperature.days.first else { return nil }

        let chance = precipitation.days.first?.averagePrecipitationProbability ?? 0
        let summary: String
        switch chance {
        case ..<0.25: summary = String(localized: "Mostly dry")
        case ..<0.5: summary = String(localized: "Some showers")
        default: summary = String(localized: "Often rainy")
        }
        return DayWeather(
            highCelsius: temp.averageHighTemperature.converted(to: .celsius).value,
            summary: summary,
            isSeasonalAverage: true,
            hint: chance > 0.4 ? String(localized: "Bring an umbrella") : nil
        )
    }
}
