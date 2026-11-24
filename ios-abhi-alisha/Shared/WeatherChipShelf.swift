import Foundation

/// The weather chips the app last fetched from Apple Weather, kept in the App Group so the
/// widgets and the Live Activity can show the same chip without calling WeatherKit themselves.
nonisolated enum WeatherChipShelf {
    nonisolated struct Chip: Codable, Hashable, Sendable {
        /// "28° · Sunny" or "Usually 28° · Mostly dry".
        let text: String
        let symbol: String
        let accessibility: String
        let fetchedAt: Date
    }

    private static var fileURL: URL? { WeddingGroup.fileURL(ActiveWedding.scopedName("weather-chips.json")) }

    static func load() -> [String: Chip] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Chip].self, from: data)) ?? [:]
    }

    /// The chip for one event, when it's no older than a day.
    static func chip(for eventID: String) -> Chip? {
        guard let chip = load()[eventID], Date().timeIntervalSince(chip.fetchedAt) < 86_400 else { return nil }
        return chip
    }

    static func store(_ chip: Chip?, for eventID: String) {
        guard let fileURL else { return }
        var all = load()
        if let chip { all[eventID] = chip } else { all.removeValue(forKey: eventID) }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
